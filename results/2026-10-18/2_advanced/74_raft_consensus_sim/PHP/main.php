<?php

require_once __DIR__ . '/cluster.php';
require_once __DIR__ . '/minstd.php';
require_once __DIR__ . '/network.php';
require_once __DIR__ . '/raft_node.php';
require_once __DIR__ . '/checker.php';

function nodeSet(array $numbers): string
{
    sort($numbers, SORT_NUMERIC);
    return $numbers ? implode(',', array_map(fn($number) => 'n' . $number, $numbers)) : '-';
}

function sameState(array $a, array $b): bool
{
    if (count($a) !== count($b)) return false;
    foreach ($a as $key => $value) if (!array_key_exists($key, $b) || $b[$key] !== $value) return false;
    return true;
}

function messageCounts(object $counts): string
{
    return 'sent ' . $counts->sent . ' delivered ' . $counts->delivered . ' inflight ' . $counts->inflight
        . ' partition ' . $counts->partition . ' rule ' . $counts->rule . ' loss ' . $counts->loss . ' down ' . $counts->down;
}

class Simulation
{
    public object $settings;
    public array $controls;
    public array $requests;
    public array $nodes = [];
    public Minstd $random;
    public Network $network;
    public Checker $checker;
    public array $elections = [];
    public array $leaders = [];
    public array $traceLines = [];
    public array $timeline = [];
    public array $gaps = [];
    public ?int $gapStart = null;
    public int $leaderTicks = 0;
    public int $multiTicks = 0;
    public int $time = 0;

    public function __construct(object $settings, array $controls, array $requests)
    {
        $this->settings = $settings;
        $this->controls = $controls;
        $this->requests = $requests;
        for ($i = 1; $i <= $settings->NODES; $i++) $this->nodes[] = new RaftNode($i);
        $this->random = new Minstd($settings->SEED);
        $this->network = new Network($settings->NODES, 'input/network.txt');
        $this->checker = new Checker();
    }

    public function node(int $number): RaftNode { return $this->nodes[$number - 1]; }
    public function trace(string $content): void { $this->traceLines[] = $this->time . ' ' . $content; }
    public function majority(int $count): bool { return 2 * $count > count($this->nodes); }
    public function electionTimer(RaftNode $node): void { $node->electionDeadline = $this->time + $this->random->range(...$this->settings->ELECTION); }
    public function send(RaftNode $node, int $destination, string $type, array $content = []): void
    {
        $this->network->send($this->time, $node->number, $destination, $type, $node->currentTerm, $content);
    }

    public function appendTo(RaftNode $node, int $destination): void
    {
        $prev = $node->next[$destination] - 1;
        $entries = array_map('copyEntry', array_slice($node->log, $prev, min($this->settings->BATCH, $node->lastIndex() - $prev)));
        $this->send($node, $destination, 'AE', ['prev' => $prev, 'prevTerm' => $node->term($prev), 'entries' => $entries, 'commit' => $node->commit]);
    }

    public function appendAll(RaftNode $node): void
    {
        foreach ($this->nodes as $other) if ($other !== $node) $this->appendTo($node, $other->number);
    }

    public function endLeadership(RaftNode $node, string $reason): void
    {
        $record = $this->leaders[$node->currentTerm];
        $record->ended = $this->time; $record->reason = $reason; $record->commit = $node->commit;
        $node->transfer = null;
    }

    public function startElection(RaftNode $node, string $trigger): void
    {
        $node->currentTerm++; $node->role = 'CANDIDATE'; $node->votedFor = $node->number;
        $node->votes = [$node->number => true]; $node->knownLeader = null;
        $this->electionTimer($node); $node->stats->elections++;
        $election = (object) ['time' => $this->time, 'node' => $node->number, 'term' => $node->currentTerm,
            'trigger' => $trigger, 'votes' => $node->votes, 'won' => null];
        $node->election = $election; $this->elections[] = $election;
        $this->trace('ELECTION n' . $node->number . ' term ' . $node->currentTerm . ' last ' . $node->lastIndex() . '/' . $node->lastTerm() . ' deadline ' . $node->electionDeadline);
        foreach ($this->nodes as $other) if ($other !== $node) $this->send($node, $other->number, 'RV', ['lastIndex' => $node->lastIndex(), 'lastTerm' => $node->lastTerm()]);
    }

    public function becomeLeader(RaftNode $node): void
    {
        $node->role = 'LEADER'; $node->knownLeader = $node->number;
        foreach ($this->nodes as $other) if ($other !== $node) {
            $node->next[$other->number] = $node->lastIndex() + 1;
            $node->match[$other->number] = 0;
        }
        $node->log[] = makeEntry($node->currentTerm, 'NOOP', 0);
        $node->stats->leaders++; $node->election->won = $this->time;
        $this->checker->leader($node);
        $this->leaders[$node->currentTerm] = (object) ['node' => $node->number, 'elected' => $this->time, 'votes' => $node->votes,
            'appended' => 1, 'ended' => null, 'reason' => 'ACTIVE', 'commit' => null];
        $this->trace('LEADER n' . $node->number . ' term ' . $node->currentTerm . ' votes ' . nodeSet(array_keys($node->votes)) . ' noop ' . $node->lastIndex());
        $this->appendAll($node);
        $node->heartbeatDeadline = $this->time + $this->settings->HEARTBEAT;
        $node->quorumDeadline = $this->time + $this->settings->QUORUM; $node->heard = [];
    }

    public function advanceCommit(RaftNode $node, int $last): void
    {
        $this->checker->commit($node, $node->commit + 1, $last, $this->time);
        $node->commit = $last;
        $first = $node->applied + 1;
        for ($index = $first; $index <= $last; $index++) {
            $entry = $node->entry($index);
            $result = applyCommand($node->store, $entry->command);
            $node->stats->applies++; $this->checker->apply($index, $entry, $result);
        }
        $node->applied = $last;
        $this->trace('APPLY n' . $node->number . ' ' . $first . '-' . $last);
    }

    public function commitCheck(RaftNode $node): void
    {
        for ($index = $node->lastIndex(); $index > $node->commit; $index--) {
            if ($node->term($index) !== $node->currentTerm) break;
            $count = 1;
            foreach ($node->match as $matched) if ($matched >= $index) $count++;
            if ($this->majority($count)) {
                $this->trace('COMMIT n' . $node->number . ' ' . ($node->commit + 1) . '-' . $index . ' term ' . $node->currentTerm);
                $this->advanceCommit($node, $index);
                break;
            }
        }
    }

    public function truncate(RaftNode $node, int $first): void
    {
        $removed = $node->lastIndex() - $first + 1;
        $node->stats->truncated += $removed;
        $this->checker->truncate($node, $first);
        $node->log = array_slice($node->log, 0, $first - 1);
        $this->trace('TRUNCATE n' . $node->number . ' from ' . $first . ' removed ' . $removed);
    }

    public function requestVote(RaftNode $node, object $message): void
    {
        $source = $message->source; $term = $message->term; $content = $message->content;
        $reason = null;
        if ($term < $node->currentTerm) $reason = 'term';
        elseif ($node->votedFor !== null && $node->votedFor !== $source) $reason = 'voted';
        elseif (!$node->candidateCurrent($content['lastIndex'], $content['lastTerm'])) $reason = 'log';
        if ($reason === null) {
            $node->votedFor = $source; $node->stats->votesGranted++; $this->electionTimer($node);
            $this->trace('VOTE n' . $node->number . ' n' . $source . ' term ' . $node->currentTerm . ' deadline ' . $node->electionDeadline);
        } else $this->trace('DENY n' . $node->number . ' n' . $source . ' term ' . $node->currentTerm . ' ' . $reason);
        $this->send($node, $source, 'RVR', ['granted' => $reason === null]);
    }

    public function voteResponse(RaftNode $node, object $message): void
    {
        if ($node->role !== 'CANDIDATE' || $message->term !== $node->currentTerm || !$message->content['granted']) return;
        $node->votes[$message->source] = true;
        $node->election->votes[$message->source] = true;
        if ($this->majority(count($node->votes))) $this->becomeLeader($node);
    }

    public function appendRequest(RaftNode $node, object $message): void
    {
        $source = $message->source; $term = $message->term; $content = $message->content;
        if ($term < $node->currentTerm) { $this->send($node, $source, 'AER', ['success' => false, 'm' => 0]); return; }
        if ($node->role === 'CANDIDATE') {
            $node->role = 'FOLLOWER';
            $this->trace('YIELD n' . $node->number . ' term ' . $node->currentTerm . ' n' . $source);
        }
        $node->knownLeader = $source; $this->electionTimer($node);
        if ($content['prev'] > $node->lastIndex() || $node->term($content['prev']) !== $content['prevTerm']) {
            $node->stats->aeFail++;
            $this->send($node, $source, 'AER', ['success' => false, 'm' => $content['prev'] > $node->lastIndex() ? $node->lastIndex() : $content['prev'] - 1]);
            return;
        }
        $node->stats->aeOk++;
        foreach ($content['entries'] as $i => $entry) {
            $index = $content['prev'] + $i + 1;
            if ($index <= $node->lastIndex() && $node->term($index) !== $entry->term) $this->truncate($node, $index);
            if ($index > $node->lastIndex()) { $node->log[] = copyEntry($entry); $node->stats->appended++; }
        }
        $m = $content['prev'] + count($content['entries']);
        $committed = min($content['commit'], $m);
        if ($committed > $node->commit) $this->advanceCommit($node, $committed);
        $this->send($node, $source, 'AER', ['success' => true, 'm' => $m]);
    }

    public function appendResponse(RaftNode $node, object $message): void
    {
        if ($node->role !== 'LEADER' || $message->term !== $node->currentTerm) return;
        $source = $message->source; $success = $message->content['success']; $m = $message->content['m'];
        $node->heard[$source] = true;
        if ($success) {
            $node->match[$source] = max($node->match[$source], $m);
            $node->next[$source] = max($node->next[$source], $m + 1);
            $this->commitCheck($node);
            if ($node->transfer !== null && $node->transfer->target === $source && !$node->transfer->sent && $node->match[$source] === $node->lastIndex()) {
                $this->timeoutNow($node);
            } elseif ($node->next[$source] <= $node->lastIndex()) $this->appendTo($node, $source);
        } else {
            $node->next[$source] = max($node->match[$source] + 1, min($node->next[$source] - 1, $m + 1));
            $this->trace('BACKTRACK n' . $node->number . ' n' . $source . ' next ' . $node->next[$source]);
            $this->appendTo($node, $source);
        }
    }

    public function receive(RaftNode $node, object $message): void
    {
        if ($message->term > $node->currentTerm) {
            $role = $node->role;
            $this->trace('TERM n' . $node->number . ' ' . $node->currentTerm . '->' . $message->term . ' ' . $message->type . ' n' . $message->source . ' ' . $role);
            if ($role === 'LEADER') $this->endLeadership($node, 'STEPDOWN');
            $node->currentTerm = $message->term; $node->votedFor = null; $node->knownLeader = null; $node->role = 'FOLLOWER';
            if ($role === 'LEADER') $this->electionTimer($node);
        }
        if ($message->type === 'RV') $this->requestVote($node, $message);
        elseif ($message->type === 'RVR') $this->voteResponse($node, $message);
        elseif ($message->type === 'AE') $this->appendRequest($node, $message);
        elseif ($message->type === 'AER') $this->appendResponse($node, $message);
        elseif ($message->term !== $node->currentTerm || $node->role !== 'FOLLOWER') {
            $this->trace('IGNORE n' . $node->number . ' TN n' . $message->source . ' term ' . $message->term);
        } else $this->startElection($node, 'transfer');
    }

    public function timeoutNow(RaftNode $node): void
    {
        $this->trace('TIMEOUTNOW n' . $node->number . ' n' . $node->transfer->target . ' term ' . $node->currentTerm . ' index ' . $node->lastIndex());
        $node->transfer->sent = true;
        $this->send($node, $node->transfer->target, 'TN');
    }

    public function transfer(int $source, int $target): void
    {
        $node = $this->node($source);
        if (!$node->up || $node->role !== 'LEADER' || $node->transfer !== null || $source === $target) {
            $this->trace('TRANSFER n' . $source . ' n' . $target . ' ignored'); return;
        }
        $this->trace('TRANSFER n' . $source . ' n' . $target . ' start match ' . $node->match[$target] . '/' . $node->lastIndex());
        $node->transfer = (object) ['target' => $target, 'sent' => false, 'deadline' => $this->time + $this->settings->ELECTION[0]];
        if ($node->match[$target] === $node->lastIndex()) $this->timeoutNow($node);
        else $this->appendTo($node, $target);
    }

    public function control(object $event): void
    {
        if ($event->kind === 'CRASH') {
            $node = $this->node($event->args[0]);
            $this->trace('CRASH n' . $node->number . ' ' . $node->role . ' term ' . $node->currentTerm);
            if ($node->role === 'LEADER') $this->endLeadership($node, 'CRASH');
            $node->up = false; $node->resetVolatile();
        } elseif ($event->kind === 'RESTART') {
            $node = $this->node($event->args[0]);
            $node->up = true; $this->electionTimer($node);
            $this->trace('RESTART n' . $node->number . ' term ' . $node->currentTerm . ' length ' . $node->lastIndex() . ' deadline ' . $node->electionDeadline);
        } elseif ($event->kind === 'PARTITION') {
            $this->network->partition($event->args);
            $this->trace('PARTITION ' . implode(' ', array_map('nodeSet', $event->args)));
        } elseif ($event->kind === 'HEAL') { $this->network->heal(); $this->trace('HEAL'); }
        else $this->transfer(...$event->args);
    }

    public function attempt(object $request): void
    {
        $request->attempts++;
        $destination = $request->destination;
        $redirected = 0;
        while (true) {
            $node = $this->node($destination);
            if (!$node->up) $reason = 'down';
            elseif ($node->role === 'LEADER') {
                if ($node->transfer !== null) $reason = 'transfer';
                else {
                    $node->log[] = makeEntry($node->currentTerm, $request->command, $request->number);
                    $this->leaders[$node->currentTerm]->appended++;
                    $request->accepted = (object) ['index' => $node->lastIndex(), 'term' => $node->currentTerm];
                    $this->trace('ACCEPT r' . $request->number . ' n' . $node->number . ' index ' . $node->lastIndex() . ' term ' . $node->currentTerm);
                    return;
                }
            } elseif ($node->knownLeader === null || $redirected >= count($this->nodes) - 1) $reason = 'noleader';
            else {
                $this->trace('REDIRECT r' . $request->number . ' n' . $node->number . ' n' . $node->knownLeader);
                $request->redirects++; $redirected++; $destination = $node->knownLeader;
                continue;
            }
            if ($request->attempts < $this->settings->ATTEMPTS) {
                $request->destination = $node->number % count($this->nodes) + 1;
                $request->scheduled = $this->time + $this->settings->RETRY;
                $this->trace('REJECT r' . $request->number . ' n' . $node->number . ' ' . $reason . ' retry n' . $request->destination . ' at ' . $request->scheduled);
            } else {
                $request->abandoned = true;
                $this->trace('REJECT r' . $request->number . ' n' . $node->number . ' ' . $reason . ' giveup');
            }
            return;
        }
    }

    public function timers(RaftNode $node): void
    {
        if ($node->role === 'LEADER') {
            if ($node->quorumDeadline === $this->time) {
                if (!$this->majority(count($node->heard) + 1)) {
                    $this->trace('STEPDOWN n' . $node->number . ' term ' . $node->currentTerm . ' heard ' . nodeSet(array_keys($node->heard)));
                    $this->endLeadership($node, 'QUORUM'); $node->role = 'FOLLOWER'; $node->knownLeader = null; $this->electionTimer($node);
                    return;
                }
                $node->heard = []; $node->quorumDeadline = $this->time + $this->settings->QUORUM;
            }
            if ($node->transfer !== null && $node->transfer->deadline === $this->time) {
                $this->trace('TRANSFER n' . $node->number . ' n' . $node->transfer->target . ' abort'); $node->transfer = null;
            }
            if ($node->heartbeatDeadline === $this->time) {
                $this->appendAll($node); $node->heartbeatDeadline = $this->time + $this->settings->HEARTBEAT;
            }
        } elseif ($node->electionDeadline === $this->time) $this->startElection($node, 'timeout');
    }

    public function endTick(): void
    {
        $this->checker->matching($this->nodes);
        $active = array_values(array_filter($this->nodes, fn($node) => $node->up && $node->role === 'LEADER'));
        foreach ($active as $node) $node->stats->leaderTicks++;
        if ($active) {
            $this->leaderTicks++;
            if (count($active) >= 2) $this->multiTicks++;
            if ($this->gapStart !== null) { $this->gaps[] = [$this->gapStart, $this->time - 1]; $this->gapStart = null; }
        } elseif ($this->gapStart === null) $this->gapStart = $this->time;
        if ($this->time % $this->settings->SAMPLE === 0) {
            $states = array_map(fn($node) => ($node->up ? $node->role[0] : 'D') . $node->currentTerm, $this->nodes);
            $this->timeline[] = 'TIMELINE ' . $this->time . ' ' . implode(' ', $states);
        }
    }

    public function simulate(): void
    {
        foreach ($this->nodes as $node) { $this->electionTimer($node); $this->trace('START n' . $node->number . ' deadline ' . $node->electionDeadline); }
        for ($this->time = 0; $this->time <= $this->settings->END; $this->time++) {
            foreach ($this->controls[$this->time] ?? [] as $event) $this->control($event);
            foreach ($this->requests as $request) if ($request->accepted === null && !$request->abandoned && $request->scheduled === $this->time) $this->attempt($request);
            foreach ($this->network->take($this->time) as $message) {
                $destination = $this->node($message->destination);
                if (!$destination->up) $this->network->resolve($message, 'down');
                elseif ($this->network->separated($message->source, $message->destination)) $this->network->resolve($message, 'partition');
                else { $this->network->resolve($message, 'delivered'); $this->receive($destination, $message); }
            }
            foreach ($this->nodes as $node) if ($node->up) $this->timers($node);
            $this->endTick();
        }
        if ($this->gapStart !== null) $this->gaps[] = [$this->gapStart, $this->settings->END];
    }
}

function leaderReport(Simulation $simulation, int $maximumTerm): array
{
    $lines = [];
    foreach ($simulation->elections as $election) {
        $result = $election->won === null ? 'LOST' : 'WON ' . $election->won;
        $lines[] = 'ELECTION ' . $election->time . ' n' . $election->node . ' term ' . $election->term . ' trigger ' . $election->trigger
            . ' votes ' . count($election->votes) . ' ' . $result;
    }
    for ($term = 1; $term <= $maximumTerm; $term++) {
        $elections = array_values(array_filter($simulation->elections, fn($election) => $election->term === $term));
        $candidateSet = [];
        foreach ($elections as $election) $candidateSet[$election->node] = true;
        $candidates = nodeSet(array_keys($candidateSet));
        $record = $simulation->leaders[$term] ?? null;
        if ($record === null) { $lines[] = 'TERM ' . $term . ' NONE candidates ' . $candidates; continue; }
        $commit = $record->ended === null ? $simulation->node($record->node)->commit : $record->commit;
        $started = $elections[0]->time;
        $lines[] = 'TERM ' . $term . ' LEADER n' . $record->node . ' elected ' . $record->elected . ' votes ' . nodeSet(array_keys($record->votes))
            . ' ended ' . ($record->ended === null ? '-' : $record->ended) . ' ' . $record->reason . ' appended ' . $record->appended
            . ' commit ' . $commit . ' candidates ' . $candidates . ' started ' . $started . ' wait ' . ($record->elected - $started);
    }
    foreach ($simulation->nodes as $node) {
        $stats = $node->stats;
        $lines[] = 'NODE n' . $node->number . ' elections ' . $stats->elections . ' leader_terms ' . $stats->leaders
            . ' leader_ticks ' . $stats->leaderTicks . ' votes_granted ' . $stats->votesGranted;
    }
    foreach ($simulation->timeline as $line) $lines[] = $line;
    $longest = 0;
    foreach ($simulation->gaps as [$first, $last]) {
        $length = $last - $first + 1; $longest = max($longest, $length);
        $lines[] = 'GAP ' . $first . '-' . $last . ' length ' . $length;
    }
    $lines[] = 'SUMMARY terms ' . $maximumTerm . ' leaders ' . count($simulation->leaders) . ' elections ' . count($simulation->elections)
        . ' leader_ticks ' . $simulation->leaderTicks . ' multi_ticks ' . $simulation->multiTicks . ' ticks ' . ($simulation->settings->END + 1)
        . ' gaps ' . count($simulation->gaps) . ' longest ' . $longest;
    return $lines;
}

function logReport(Simulation $simulation): array
{
    $lines = [];
    $committed = count($simulation->checker->committed);
    foreach ($simulation->nodes as $node) {
        $lines[] = 'NODE n' . $node->number . ' ' . ($node->up ? $node->role : 'DOWN') . ' term ' . $node->currentTerm
            . ' voted ' . ($node->votedFor === null ? '-' : 'n' . $node->votedFor) . ' commit ' . $node->commit
            . ' applied ' . $node->applied . ' length ' . $node->lastIndex();
        foreach ($node->log as $i => $entry) $lines[] = ($i + 1) . ' ' . $entry->term . ' ' . $entry->command . ($entry->request === 0 ? '' : ' r' . $entry->request);
    }
    $prefix = 0;
    $shortest = min(array_map(fn($node) => $node->lastIndex(), $simulation->nodes));
    while ($prefix < $shortest) {
        $equal = true;
        foreach ($simulation->nodes as $node) if (!sameEntry($node->entry($prefix + 1), $simulation->nodes[0]->entry($prefix + 1))) { $equal = false; break; }
        if (!$equal) break;
        $prefix++;
    }
    $lines[] = 'AGREE prefix ' . $prefix . ' committed ' . $committed;
    foreach ($simulation->nodes as $node) {
        $common = 0;
        while ($common < min($node->lastIndex(), $committed) && $node->term($common + 1) === $simulation->checker->committed[$common + 1]->term) $common++;
        $stats = $node->stats;
        $lines[] = 'DIFF n' . $node->number . ' common ' . $common . ' behind ' . ($committed - $common) . ' extra ' . ($node->lastIndex() - $common)
            . ' ae_ok ' . $stats->aeOk . ' ae_fail ' . $stats->aeFail . ' appended ' . $stats->appended . ' truncated ' . $stats->truncated . ' applies ' . $stats->applies;
    }
    return $lines;
}

function finalStates(Simulation $simulation): object
{
    $committed = count($simulation->checker->committed);
    $reference = [];
    $wanted = [];
    foreach ($simulation->nodes as $node) $wanted[$node->applied] = true;
    $replays = [0 => []];
    for ($index = 1; $index <= $committed; $index++) {
        applyCommand($reference, $simulation->checker->applied[$index]->entry->command);
        if (isset($wanted[$index])) $replays[$index] = $reference;
    }
    $requests = [];
    foreach ($simulation->requests as $item) {
        $request = clone $item;
        if ($request->accepted === null) $request->status = $request->abandoned ? 'FAILED' : 'WAITING';
        else {
            $index = $request->accepted->index;
            $term = $request->accepted->term;
            $record = $simulation->checker->committed[$index] ?? null;
            if ($record !== null && $record->term === $term) {
                $request->status = 'COMMITTED';
                $request->latency = $record->time - $request->time;
                $request->result = $simulation->checker->applied[$index]->result;
            } else {
                $retained = false;
                foreach ($simulation->nodes as $node) if ($node->lastIndex() >= $index && $node->term($index) === $term) { $retained = true; break; }
                $request->status = $retained ? 'UNCOMMITTED' : 'LOST';
            }
        }
        $requests[] = $request;
    }
    return (object) compact('reference', 'replays', 'requests');
}

function stateReport(Simulation $simulation, object $states): array
{
    $lines = [];
    foreach ($simulation->nodes as $node) {
        $identical = sameState($node->store, $states->replays[$node->applied]);
        $lines[] = 'NODE n' . $node->number . ' ' . ($node->up ? 'UP' : 'DOWN') . ' applied ' . $node->applied
            . ' keys ' . count($node->store) . ' replay ' . ($identical ? 'match' : 'mismatch');
        $keys = array_keys($node->store); sort($keys, SORT_STRING);
        foreach ($keys as $key) $lines[] = $key . ' ' . $node->store[$key];
    }
    $counts = ['COMMITTED' => 0, 'UNCOMMITTED' => 0, 'LOST' => 0, 'FAILED' => 0, 'WAITING' => 0];
    $latencies = $keys = [];
    foreach ($states->requests as $request) {
        $counts[$request->status]++;
        $status = $request->status;
        if ($request->accepted !== null) {
            $status .= ' index ' . $request->accepted->index . ' term ' . $request->accepted->term;
            if ($request->status === 'COMMITTED') {
                $status .= ' latency ' . $request->latency . ' result ' . $request->result;
                $latencies[] = $request->latency;
            }
        } elseif ($request->status === 'WAITING') $status .= ' next ' . $request->scheduled;
        $lines[] = 'REQUEST r' . $request->number . ' at ' . $request->time . ' n' . $request->startNode . ' ' . $request->command
            . ' attempts ' . $request->attempts . ' redirects ' . $request->redirects . ' ' . $status;
        $key = explode(' ', $request->command)[1];
        if (!isset($keys[$key])) $keys[$key] = (object) ['requests' => 0, 'committed' => 0];
        $keys[$key]->requests++;
        if ($request->status === 'COMMITTED') $keys[$key]->committed++;
    }
    $orderedKeys = array_keys($keys); sort($orderedKeys, SORT_STRING);
    foreach ($orderedKeys as $key) {
        $tally = $keys[$key];
        $lines[] = 'KEY ' . $key . ' requests ' . $tally->requests . ' committed ' . $tally->committed
            . ' final ' . (array_key_exists($key, $states->reference) ? $states->reference[$key] : 'missing');
    }
    $lines[] = 'REQUESTS total ' . count($states->requests) . ' committed ' . $counts['COMMITTED'] . ' uncommitted ' . $counts['UNCOMMITTED']
        . ' lost ' . $counts['LOST'] . ' failed ' . $counts['FAILED'] . ' waiting ' . $counts['WAITING'];
    $lines[] = 'LATENCY count ' . count($latencies) . ' total ' . array_sum($latencies)
        . ' min ' . ($latencies ? min($latencies) : 0) . ' max ' . ($latencies ? max($latencies) : 0);
    return $lines;
}

function safetyReport(Simulation $simulation, int $maximumTerm): array
{
    $lines = $simulation->checker->lines($maximumTerm);
    $network = $simulation->network;
    $lines[] = 'MESSAGES ' . messageCounts($network->total);
    foreach (TYPES as $type) $lines[] = 'TYPE ' . $type . ' ' . messageCounts($network->types[$type]);
    foreach ($network->links as $link) {
        $counts = $link->counts;
        $dropped = $counts->partition + $counts->rule + $counts->loss + $counts->down;
        $lines[] = 'LINK n' . $link->source . '->n' . $link->destination . ' delay ' . $link->delay . ' loss ' . $link->loss
            . ' sent ' . $counts->sent . ' delivered ' . $counts->delivered . ' dropped ' . $dropped;
    }
    $lines[] = 'DRAWS ' . $simulation->random->draws;
    $lines[] = 'RESULT ' . (array_sum($simulation->checker->violations) === 0 ? 'SAFE' : 'UNSAFE');
    return $lines;
}

$input = readCluster();
$simulation = new Simulation($input->settings, $input->controls, $input->requests);
$simulation->simulate();
$maximumTerm = max(array_map(fn($node) => $node->currentTerm, $simulation->nodes));
$states = finalStates($simulation);
$reports = ['trace.txt' => $simulation->traceLines, 'leaders.txt' => leaderReport($simulation, $maximumTerm),
    'logs.txt' => logReport($simulation), 'state.txt' => stateReport($simulation, $states), 'safety.txt' => safetyReport($simulation, $maximumTerm)];
if (!is_dir('output')) mkdir('output', 0777, true);
foreach ($reports as $name => $lines) file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
