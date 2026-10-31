<?php

require_once __DIR__ . '/network.php';
require_once __DIR__ . '/clocks.php';
require_once __DIR__ . '/processes.php';
require_once __DIR__ . '/snapshot.php';
require_once __DIR__ . '/analysis.php';

function readParameters() {
    $result = ['compares' => [], 'cuts' => [], 'predicates' => []];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $words = explode(' ', $line);
        $key = array_shift($words);
        if ($key === 'COMPARE') $result['compares'][] = $words;
        elseif ($key === 'CUT') $result['cuts'][] = array_map('intval', $words);
        elseif ($key === 'PREDICATE') $result['predicates'][] = (int)$words[0];
        else $result[strtolower($key)] = (int)$words[0];
    }
    return $result;
}

class SchedulingQueue {
    public $heap = [];
    public $serial = 0;

    public function compare($left, $right) {
        return ($left->time <=> $right->time) ?: (($left->process <=> $right->process) ?: ($left->serial <=> $right->serial));
    }

    public function push($item) {
        $item->serial = ++$this->serial;
        $index = count($this->heap);
        $this->heap[] = $item;
        while ($index > 0) {
            $parent = intdiv($index - 1, 2);
            if ($this->compare($this->heap[$parent], $item) <= 0) break;
            $this->heap[$index] = $this->heap[$parent];
            $index = $parent;
        }
        $this->heap[$index] = $item;
    }

    public function pop() {
        $first = $this->heap[0];
        $last = array_pop($this->heap);
        if ($this->heap) {
            $index = 0;
            while (2 * $index + 1 < count($this->heap)) {
                $child = 2 * $index + 1;
                if ($child + 1 < count($this->heap) && $this->compare($this->heap[$child + 1], $this->heap[$child]) < 0) $child++;
                if ($this->compare($last, $this->heap[$child]) <= 0) break;
                $this->heap[$index] = $this->heap[$child];
                $index = $child;
            }
            $this->heap[$index] = $last;
        }
        return $first;
    }
}

class Simulation {
    public $names;
    public $params;
    public $raw;
    public $generator;
    public $processes = [];
    public $channels = [];
    public $channelTable;
    public $events = [];
    public $messages = [];
    public $copies = [];
    public $snapshots = [];
    public $snapshotByName = [];
    public $timeline = [];
    public $time = 0;
    public $initialTotal = 0;
    public $queue;

    public function __construct($topology, $programs, $params, $raw) {
        $this->names = $topology['names'];
        $this->params = $params;
        $this->raw = $raw;
        $this->generator = new Minstd($params['seed']);
        foreach ($programs as $program) $this->processes[] = new ProcessState($program, count($this->names));
        $this->channelTable = array_fill(0, count($this->names), []);
        foreach ($topology['channels'] as $specification) {
            $channel = new Channel($specification, count($this->names));
            $this->channels[] = $channel;
            $this->channelTable[$channel->source][$channel->destination] = $channel;
        }
        foreach ($this->processes as $process) $this->initialTotal += $process->initial;
        $this->queue = new SchedulingQueue();
        foreach (expandScheduled($programs, $params['end']) as $item) $this->queue->push($item);
    }

    public function run() {
        while ($this->queue->heap && $this->queue->heap[0]->time <= $this->params['end']) {
            $item = $this->queue->pop();
            $this->time = $item->time;
            if (isset($item->packet)) $this->arrive($item->packet);
            else $this->execute($this->processes[$item->process], $item->action);
        }
        return $this;
    }

    public function event($process, $type, $details = []) {
        advance($process, $type === 'RECV' ? $details['copy']->message->event : null);
        $event = (object)array_merge($details, ['type' => $type, 'number' => count($this->events) + 1, 'process' => $process->index,
            'local' => count($process->events) + 1, 'time' => $this->time, 'L' => $process->L, 'V' => $process->V, 'balance' => $process->balance]);
        $process->events[] = $event;
        $process->counts[$type]++;
        $process->minimum = min($process->minimum, $process->balance);
        $this->events[] = $event;
        $this->timeline[] = (object)['event' => $event];
        return $event;
    }

    public function dispatch($packet) {
        $this->channelTable[$packet->source][$packet->destination]->dispatch($packet, $this->time, $this->generator);
        $this->queue->push((object)['time' => $packet->arrival, 'process' => $packet->destination, 'packet' => $packet]);
    }

    public function send($process, $kind, $tag, $amount, $destination = null) {
        $message = (object)['id' => count($this->messages) + 1, 'source' => $process->index, 'destination' => $destination,
            'kind' => $kind, 'tag' => $tag, 'amount' => $amount, 'stamp' => $kind === 'BCAST' ? $process->B : null, 'copies' => []];
        $this->messages[] = $message;
        $message->event = $this->event($process, $kind === 'BCAST' ? 'BCAST' : 'SEND', ['message' => $message]);
        $destinations = [];
        if ($kind === 'BCAST') {
            foreach ($this->processes as $other) if ($other->index !== $process->index) $destinations[] = $other->index;
        } else $destinations[] = $destination;
        foreach ($destinations as $target) {
            $copy = (object)['order' => count($this->copies), 'message' => $message, 'source' => $process->index, 'destination' => $target,
                'received' => null, 'delivery' => null, 'fifoWait' => false, 'causalWait' => false, 'missing' => [], 'place' => null];
            $this->copies[] = $copy;
            $message->copies[] = $copy;
            $this->dispatch($copy);
        }
    }

    public function execute($process, $action, $sender = null) {
        if ($action['type'] === 'LOCAL') $this->event($process, 'LOCAL', ['label' => $action['label']]);
        elseif ($action['type'] === 'SNAPSHOT') $this->initiate($process, $action['name']);
        elseif ($action['type'] === 'BROADCAST') {
            $process->B[$process->index]++;
            $this->send($process, 'BCAST', $action['tag'], 0);
        } else {
            $destination = $action['destination'] === 'SENDER' ? $sender : $action['destination'];
            if ($action['type'] === 'SEND') $this->send($process, 'P2P', $action['tag'], 0, $destination);
            elseif ($action['amount'] > $process->balance) $this->event($process, 'NOFUNDS', ['destination' => $destination, 'amount' => $action['amount']]);
            else {
                $process->balance -= $action['amount'];
                $process->sent += $action['amount'];
                $this->send($process, 'P2P', 'transfer', $action['amount'], $destination);
            }
        }
    }

    public function arrive($packet) {
        $process = $this->processes[$packet->destination];
        $source = $packet->source;
        if ($this->raw) $this->accept($packet);
        elseif ($packet->sequence !== $process->next[$source]) {
            $packet->fifoWait = true;
            $packet->place = 'fifo';
            $process->reorder[$source][$packet->sequence] = $packet;
            $this->channelTable[$source][$process->index]->buffered++;
        } else {
            $this->accept($packet);
            while (isset($process->reorder[$source][$process->next[$source]])) {
                $sequence = $process->next[$source];
                $next = $process->reorder[$source][$sequence];
                unset($process->reorder[$source][$sequence]);
                $this->accept($next);
            }
        }
        $held = count($process->hold);
        foreach ($process->reorder as $buffer) $held += count($buffer);
        $process->maxHeld = max($process->maxHeld, $held);
    }

    public function accept($packet) {
        $process = $this->processes[$packet->destination];
        $process->next[$packet->source]++;
        $packet->place = null;
        if (isset($packet->marker)) {
            $this->marker($packet);
            return;
        }
        foreach ($this->snapshots as $snapshot) {
            if ($snapshot->records[$process->index] !== null && $snapshot->accepted[$packet->source][$process->index] === null) {
                $snapshot->channels[$packet->source][$process->index][] = $packet;
            }
        }
        if ($packet->message->kind === 'P2P') $this->deliver($packet);
        elseif ($this->raw || deliverable($packet, $process->B)) {
            $this->deliver($packet);
            if (!$this->raw) {
                while (true) {
                    $index = null;
                    foreach ($process->hold as $i => $copy) if (deliverable($copy, $process->B)) {
                        $index = $i;
                        break;
                    }
                    if ($index === null) break;
                    $copy = array_splice($process->hold, $index, 1)[0];
                    $this->deliver($copy);
                }
            }
        } else {
            $packet->causalWait = true;
            $packet->missing = missingProcesses($packet, $process->B);
            $packet->place = 'causal';
            $process->hold[] = $packet;
        }
    }

    public function deliver($copy) {
        $process = $this->processes[$copy->destination];
        if ($copy->message->kind === 'BCAST') $process->B[$copy->source]++;
        $process->balance += $copy->message->amount;
        $process->received += $copy->message->amount;
        $copy->delivery = $this->time;
        $copy->place = null;
        $copy->received = $this->event($process, 'RECV', ['copy' => $copy, 'message' => $copy->message]);
        $process->deliveries[] = $copy;
        foreach ($process->reactions as $rule) if ($rule['tag'] === $copy->message->tag) $this->execute($process, $rule['action'], $copy->source);
    }

    public function initiate($process, $name) {
        if (!isset($this->snapshotByName[$name])) {
            $snapshot = new Snapshot($name, $this->time, count($this->names));
            $this->snapshots[] = $snapshot;
            $this->snapshotByName[$name] = $snapshot;
        } else $snapshot = $this->snapshotByName[$name];
        if ($snapshot->records[$process->index] !== null) $snapshot->ignored[] = ['process' => $process->index, 'time' => $this->time];
        else $this->record($process, $snapshot, 'initiate');
    }

    public function record($process, $snapshot, $reason) {
        $record = $snapshot->record($process, $this->time, $reason);
        $this->timeline[] = (object)['record' => $record];
        for ($destination = 0; $destination < count($this->names); $destination++) {
            if ($destination === $process->index) continue;
            $snapshot->dispatched[$process->index][$destination] = $this->time;
            $this->dispatch((object)['marker' => $snapshot, 'source' => $process->index, 'destination' => $destination]);
        }
    }

    public function marker($packet) {
        $snapshot = $packet->marker;
        $process = $this->processes[$packet->destination];
        if ($snapshot->records[$process->index] === null) $this->record($process, $snapshot, 'marker ' . $this->names[$packet->source]);
        $snapshot->accepted[$packet->source][$process->index] = $this->time;
        $snapshot->remaining--;
        if ($snapshot->remaining === 0) $snapshot->completed = $this->time;
    }
}

function yesNo($value) {
    return $value ? 'yes' : 'no';
}

function messageName($message) {
    return 'm' . $message->id;
}

function eventName($event, $names) {
    return $names[$event->process] . '.' . $event->local;
}

function copyName($copy, $names) {
    return messageName($copy->message) . '->' . $names[$copy->destination];
}

function nameList($indices, $names) {
    $result = [];
    foreach ($indices as $index) $result[] = $names[$index];
    return implode(',', $result);
}

function traceReport($simulation) {
    $names = $simulation->names;
    $lines = [];
    foreach ($simulation->events as $event) {
        if ($event->type === 'LOCAL') $details = $event->label;
        elseif ($event->type === 'NOFUNDS') $details = 'to ' . $names[$event->destination] . ' amount ' . $event->amount . ' balance ' . $event->balance;
        else {
            $message = $event->message;
            if ($event->type === 'BCAST') $details = messageName($message) . ' tag ' . $message->tag;
            else {
                $route = $event->type === 'SEND' ? 'to ' . $names[$message->destination] : 'from ' . $names[$message->source];
                $details = messageName($message) . ' ' . $route . ' tag ' . $message->tag;
                if ($message->tag === 'transfer') $details .= ' amount ' . $message->amount . ' balance ' . $event->balance;
            }
        }
        $lines[] = $event->number . ' t=' . $event->time . ' ' . eventName($event, $names) . ' ' . $event->type . ' ' . $details . ' L=' . $event->L . ' V=' . vector($event->V);
    }
    $delivered = 0;
    foreach ($simulation->copies as $copy) if ($copy->received !== null) $delivered++;
    $lines[] = 'SUMMARY events ' . count($simulation->events) . ' messages ' . count($simulation->messages) . ' copies ' . count($simulation->copies)
        . ' delivered ' . $delivered . ' undelivered ' . (count($simulation->copies) - $delivered) . ' draws ' . $simulation->generator->draws;
    foreach ($simulation->processes as $process) {
        $lines[] = 'FINAL ' . $names[$process->index] . ' events ' . count($process->events) . ' L=' . $process->L . ' V=' . vector($process->V)
            . ' B=' . vector($process->B) . ' balance ' . $process->balance . ' in ' . $process->received . ' out ' . $process->sent
            . ' refused ' . $process->counts['NOFUNDS'] . ' min ' . $process->minimum;
    }
    foreach ($simulation->processes as $process) {
        $lines[] = 'COUNTS ' . $names[$process->index] . ' local ' . $process->counts['LOCAL'] . ' nofunds ' . $process->counts['NOFUNDS']
            . ' send ' . $process->counts['SEND'] . ' bcast ' . $process->counts['BCAST'] . ' recv ' . $process->counts['RECV'];
    }
    return $lines;
}

function broadcastOrder($process) {
    $order = [];
    foreach ($process->events as $event) {
        if ($event->type === 'BCAST' || ($event->type === 'RECV' && $event->message->kind === 'BCAST')) $order[] = $event->message->id;
    }
    return $order;
}

function waitMode($copy, $names) {
    if ($copy->causalWait) return ($copy->fifoWait ? 'fifo+causal' : 'causal') . ' ' . nameList($copy->missing, $names);
    return $copy->fifoWait ? 'fifo' : 'direct';
}

function deliveriesReport($simulation) {
    $names = $simulation->names;
    $copies = $simulation->copies;
    $lines = [];
    foreach ($simulation->processes as $process) {
        $lines[] = 'PROCESS ' . $names[$process->index];
        $counts = ['direct' => 0, 'fifo' => 0, 'causal' => 0, 'both' => 0];
        $waiting = $maxWait = 0;
        foreach ($process->deliveries as $i => $copy) {
            $message = $copy->message;
            $wait = $copy->delivery - $copy->arrival;
            $waiting += $wait;
            $maxWait = max($maxWait, $wait);
            $mode = $copy->causalWait ? ($copy->fifoWait ? 'both' : 'causal') : ($copy->fifoWait ? 'fifo' : 'direct');
            $counts[$mode]++;
            $lines[] = ($i + 1) . ' ' . messageName($message) . ' from ' . $names[$copy->source] . ' ' . $message->kind . ' tag ' . $message->tag
                . ' sent ' . $message->event->time . ' arrived ' . $copy->arrival . ' delivered ' . $copy->delivery . ' wait ' . $wait . ' ' . waitMode($copy, $names);
        }
        $undelivered = [];
        foreach ($copies as $copy) if ($copy->destination === $process->index && $copy->received === null) $undelivered[] = $copy;
        foreach ($undelivered as $copy) {
            if ($copy->arrival > $simulation->params['end']) continue;
            $message = $copy->message;
            $place = $copy->place === 'fifo' ? 'fifo' : 'causal ' . nameList($copy->missing, $names);
            $lines[] = 'HELD ' . messageName($message) . ' from ' . $names[$copy->source] . ' ' . $message->kind . ' tag ' . $message->tag
                . ' sent ' . $message->event->time . ' arrived ' . $copy->arrival . ' ' . $place;
        }
        foreach ($undelivered as $copy) {
            if ($copy->arrival <= $simulation->params['end']) continue;
            $message = $copy->message;
            $lines[] = 'TRANSIT ' . messageName($message) . ' from ' . $names[$copy->source] . ' ' . $message->kind . ' tag ' . $message->tag
                . ' sent ' . $message->event->time . ' arrival ' . $copy->arrival;
        }
        $lines[] = 'TOTAL delivered ' . count($process->deliveries) . ' direct ' . $counts['direct'] . ' fifo ' . $counts['fifo'] . ' causal ' . $counts['causal']
            . ' both ' . $counts['both'] . ' wait ' . $waiting . ' max_wait ' . $maxWait . ' max_held ' . $process->maxHeld;
        $order = broadcastOrder($process);
        $lines[] = 'BCASTS ' . ($order ? implode(' ', array_map(fn($id) => 'm' . $id, $order)) : 'none');
    }
    foreach ($simulation->channels as $channel) {
        $delay = $channel->low === $channel->high ? (string)$channel->low : $channel->low . '-' . $channel->high;
        $lines[] = 'CHANNEL ' . $names[$channel->source] . '->' . $names[$channel->destination] . ' ' . $channel->type . ' ' . $delay
            . ' messages ' . $channel->messages . ' markers ' . $channel->markers . ' buffered ' . $channel->buffered
            . ' max_delay ' . $channel->maxDelay . ' entries ' . $channel->entries;
    }
    $tags = [];
    foreach ($copies as $copy) $tags[$copy->message->tag] = true;
    $tags = array_keys($tags);
    sort($tags, SORT_STRING);
    foreach ($tags as $tag) {
        $count = $delivered = $latency = $maximum = 0;
        foreach ($copies as $copy) {
            if ($copy->message->tag !== $tag) continue;
            $count++;
            if ($copy->received !== null) {
                $delivered++;
                $value = $copy->delivery - $copy->message->event->time;
                $latency += $value;
                $maximum = max($maximum, $value);
            }
        }
        $lines[] = 'TAG ' . $tag . ' copies ' . $count . ' delivered ' . $delivered . ' latency ' . $latency . ' max ' . $maximum;
    }
    $broadcasts = [];
    foreach ($simulation->messages as $message) if ($message->kind === 'BCAST') $broadcasts[] = $message;
    foreach ($broadcasts as $message) {
        $stable = 0;
        $all = true;
        foreach ($message->copies as $copy) {
            if ($copy->received === null) $all = false;
            else $stable = max($stable, $copy->delivery);
        }
        $lines[] = 'STABLE ' . messageName($message) . ' ' . $names[$message->source] . ' tag ' . $message->tag . ' sent ' . $message->event->time . ' stable ' . ($all ? $stable : 'none');
    }
    $orders = [];
    foreach ($simulation->processes as $process) $orders[] = broadcastOrder($process);
    $disagreements = 0;
    for ($i = 0; $i < count($broadcasts); $i++) for ($j = $i + 1; $j < count($broadcasts); $j++) {
        $earlier = $later = [];
        foreach ($names as $process => $name) {
            $first = array_search($broadcasts[$i]->id, $orders[$process], true);
            $second = array_search($broadcasts[$j]->id, $orders[$process], true);
            if ($first === false || $second === false) continue;
            if ($first < $second) $earlier[] = $process;
            else $later[] = $process;
        }
        if ($earlier && $later) {
            $disagreements++;
            $lines[] = 'DISAGREE ' . messageName($broadcasts[$i]) . ' ' . messageName($broadcasts[$j]) . ' ' . nameList($earlier, $names) . ' ' . nameList($later, $names);
        }
    }
    $lines[] = 'DISAGREEMENTS ' . $disagreements;
    return $lines;
}

function cutVerdict($result, $names) {
    if (!$result['orphans']) return 'yes';
    $values = [];
    foreach ($result['orphans'] as $copy) $values[] = copyName($copy, $names);
    return 'no ' . implode(' ', $values);
}

function snapshotDetails($simulation, $snapshot) {
    $cut = $snapshot->cut();
    $result = inspectCut($simulation->processes, $simulation->copies, $cut);
    $captured = [];
    $balances = $pending = 0;
    foreach ($snapshot->records as $record) {
        $balances += $record->balance;
        $pending += count($record->pending);
        foreach ($record->pending as $copy) $captured[] = $copy;
    }
    $channels = $channelMoney = 0;
    foreach ($simulation->channels as $channel) {
        $copies = $snapshot->channels[$channel->source][$channel->destination];
        $channels += count($copies);
        foreach ($copies as $copy) {
            $captured[] = $copy;
            $channelMoney += $copy->message->amount;
        }
    }
    usort($captured, fn($a, $b) => $a->order <=> $b->order);
    $match = count($captured) === count($result['transit']);
    if ($match) foreach ($captured as $i => $copy) if ($copy !== $result['transit'][$i]) {
        $match = false;
        break;
    }
    $vectorVerdict = true;
    foreach ($snapshot->records as $record) if (!lessEqual($record->V, $cut)) $vectorVerdict = false;
    return ['cut' => $cut, 'result' => $result, 'balances' => $balances, 'pending' => $pending, 'channels' => $channels,
        'channelMoney' => $channelMoney, 'money' => $balances + $channelMoney, 'match' => $match, 'vectorVerdict' => $vectorVerdict];
}

function snapshotsReport($simulation, $raw) {
    $names = $simulation->names;
    $lines = [];
    foreach ($simulation->snapshots as $snapshot) {
        $details = snapshotDetails($simulation, $snapshot);
        $lines[] = 'SNAPSHOT ' . $snapshot->name . ' started ' . $snapshot->started . ' completed ' . $snapshot->completed;
        foreach ($snapshot->records as $record) {
            $pending = [];
            foreach ($record->pending as $copy) $pending[] = messageName($copy->message);
            $lines[] = 'RECORD ' . $names[$record->process] . ' t=' . $record->time . ' ' . $record->reason . ' balance ' . $record->balance
                . ' L=' . $record->L . ' V=' . vector($record->V) . ' pending ' . ($pending ? implode(' ', $pending) : 'none');
        }
        foreach ($simulation->channels as $channel) {
            $source = $channel->source;
            $destination = $channel->destination;
            $copies = $snapshot->channels[$source][$destination];
            $values = [];
            foreach ($copies as $copy) $values[] = messageName($copy->message) . ($copy->message->amount === 0 ? '' : ':' . $copy->message->amount);
            $lines[] = 'CHANNEL ' . $names[$source] . '->' . $names[$destination] . ' marker ' . $snapshot->dispatched[$source][$destination]
                . ' ' . $snapshot->accepted[$source][$destination] . ' state ' . ($values ? implode(' ', $values) : 'empty');
        }
        foreach ($snapshot->ignored as $ignored) $lines[] = 'IGNORED ' . $names[$ignored['process']] . ' t=' . $ignored['time'];
        $lines[] = 'CUT ' . vector($details['cut']) . ' consistent ' . cutVerdict($details['result'], $names) . ' vector ' . yesNo($details['vectorVerdict']);
        $lines[] = 'TRANSIT channels ' . $details['channels'] . ' pending ' . $details['pending'] . ' cut ' . count($details['result']['transit']) . ' match ' . yesNo($details['match']);
        $lines[] = 'MONEY balances ' . $details['balances'] . ' channels ' . $details['channelMoney'] . ' total ' . $details['money']
            . ' initial ' . $simulation->initialTotal . ' conserved ' . yesNo($details['money'] === $simulation->initialTotal);
    }
    foreach ($raw->snapshots as $snapshot) {
        $details = snapshotDetails($raw, $snapshot);
        $lines[] = 'RAW ' . $snapshot->name . ' completed ' . $snapshot->completed . ' cut ' . vector($details['cut'])
            . ' consistent ' . cutVerdict($details['result'], $names) . ' money ' . $details['money'] . ' conserved ' . yesNo($details['money'] === $raw->initialTotal);
    }
    return $lines;
}

function rangeNotation($events, $names) {
    $parts = [];
    for ($start = 0; $start < count($events);) {
        $end = $start;
        while ($end + 1 < count($events) && $events[$end + 1]->process === $events[$start]->process) $end++;
        $parts[] = eventName($events[$start], $names) . ($start === $end ? '' : '-' . $events[$end]->local);
        $start = $end + 1;
    }
    return implode(' ', $parts);
}

function longestChain($simulation) {
    $current = $simulation->events[0];
    foreach ($simulation->events as $event) if ($event->L > $current->L) $current = $event;
    $chain = [$current];
    while ($current->L > 1) {
        if ($current->type === 'RECV' && $current->copy->message->event->L === $current->L - 1) $current = $current->copy->message->event;
        else $current = $simulation->processes[$current->process]->events[$current->local - 2];
        $chain[] = $current;
    }
    return array_reverse($chain);
}

function analysisReport($simulation, $raw) {
    $names = $simulation->names;
    $events = $simulation->events;
    $processes = $simulation->processes;
    $copies = $simulation->copies;
    $params = $simulation->params;
    $lines = [];
    $graph = eventGraph($processes, $events, $copies);
    $byName = [];
    foreach ($events as $event) $byName[eventName($event, $names)] = $event;
    foreach ($params['compares'] as [$firstName, $secondName]) {
        $first = $byName[$firstName];
        $second = $byName[$secondName];
        $vectorRelation = relation($first->V, $second->V);
        $path = breadthFirst($graph, $first->number - 1, $second->number - 1);
        $graphRelation = '->';
        if ($path === null) {
            $path = breadthFirst($graph, $second->number - 1, $first->number - 1);
            $graphRelation = $path === null ? '||' : '<-';
        }
        $lines[] = 'COMPARE ' . $firstName . ' ' . $vectorRelation . ' ' . $secondName . ' L=' . $first->L . ',' . $second->L
            . ' graph ' . $graphRelation . ' agree ' . yesNo($vectorRelation === $graphRelation);
        if ($path !== null) {
            $sequence = [];
            foreach ($path as $index) $sequence[] = $events[$index];
            $messages = 0;
            for ($i = 1; $i < count($sequence); $i++) if ($sequence[$i]->process !== $sequence[$i - 1]->process) $messages++;
            $lines[] = 'PATH length ' . count($sequence) . ' messages ' . $messages . ' ' . rangeNotation($sequence, $names);
        }
        foreach ([$first, $second] as $event) {
            $future = [];
            foreach ($processes as $process) {
                $count = 0;
                foreach ($process->events as $other) if ($other->V[$event->process] < $event->local) $count++;
                $future[] = $count;
            }
            $lines[] = 'WINDOW ' . eventName($event, $names) . ' past ' . vector($event->V) . ' future ' . vector($future);
        }
    }
    $concurrency = concurrentPairs($events, count($names));
    $lines[] = 'CONCURRENCY events ' . count($events) . ' pairs ' . ($concurrency['ordered'] + $concurrency['concurrent'])
        . ' ordered ' . $concurrency['ordered'] . ' concurrent ' . $concurrency['concurrent'] . ' same_lamport ' . $concurrency['sameLamport']
        . ' inversions ' . $concurrency['inversions'];
    for ($i = 0; $i < count($names); $i++) for ($j = $i + 1; $j < count($names); $j++) $lines[] = 'PAIR ' . $names[$i] . ' ' . $names[$j] . ' ' . $concurrency['pairs'][$i][$j];
    $chain = longestChain($simulation);
    $lines[] = 'CHAIN length ' . count($chain) . ' ' . rangeNotation($chain, $names);
    $deliveries = deliveryRelations($processes);
    foreach ($deliveries['races'] as $item) {
        $lines[] = 'RACE ' . $names[$item['process']] . ' ' . messageName($item['first']->message) . ' ' . $names[$item['first']->source]
            . ' ' . messageName($item['second']->message) . ' ' . $names[$item['second']->source];
    }
    $lines[] = 'RACES ' . count($deliveries['races']);
    foreach ($deliveries['violations'] as $item) {
        $lines[] = 'VIOLATION ' . $names[$item['process']] . ' ' . messageName($item['first']->message) . ' ' . $names[$item['first']->source]
            . ' overtook ' . messageName($item['second']->message) . ' ' . $names[$item['second']->source];
    }
    $lines[] = 'VIOLATIONS causal ' . count($deliveries['violations']) . ' fifo ' . $deliveries['fifo'];
    $rawRelations = deliveryRelations($raw->processes);
    $rawDelivered = 0;
    foreach ($raw->copies as $copy) if ($copy->received !== null) $rawDelivered++;
    $lines[] = 'RAW events ' . count($raw->events) . ' delivered ' . $rawDelivered . ' causal ' . count($rawRelations['violations']) . ' fifo ' . $rawRelations['fifo'];
    foreach ($params['cuts'] as $cut) {
        $result = inspectCut($processes, $copies, $cut);
        $orphans = [];
        foreach ($result['orphans'] as $copy) $orphans[] = copyName($copy, $names);
        $status = !$orphans ? 'consistent' : 'inconsistent orphans ' . implode(' ', $orphans);
        $lines[] = 'CUT ' . vector($cut) . ' ' . $status . ' transit ' . count($result['transit']) . ' money ' . $result['money'] . ' initial ' . $simulation->initialTotal;
    }
    $cuts = countCuts($processes, $params['cutcount'], $simulation->initialTotal);
    $lines[] = 'CUTCOUNT t=' . $params['cutcount'] . ' events ' . vector($cuts['bounds']) . ' product ' . $cuts['product'] . ' consistent ' . $cuts['consistent'];
    $lines[] = 'LEVELS ' . implode(' ', $cuts['levels']);
    foreach ($params['predicates'] as $threshold) {
        $result = predicate($cuts, $threshold);
        $lines[] = 'PREDICATE transit>=' . $threshold . ' cuts ' . $result['count'] . ' possibly ' . yesNo($result['possibly']) . ' definitely ' . yesNo($result['definitely']);
    }
    return $lines;
}

function writeText(&$characters, $position, $text) {
    for ($i = 0; $i < strlen($text); $i++) $characters[$position + $i] = $text[$i];
}

function diagramHeader($names, $label) {
    $characters = str_repeat(' ', 8 * count($names) - 1);
    writeText($characters, 0, '    ' . $label);
    foreach ($names as $i => $name) writeText($characters, 8 * $i + 6, $name);
    return rtrim($characters);
}

function diagramLine($entry, $names, $value) {
    $characters = str_repeat(' ', 8 * count($names) - 1);
    $columns = [];
    foreach ($names as $i => $name) $columns[] = 8 * $i + 6;
    writeText($characters, 0, str_pad((string)$value, 5, ' ', STR_PAD_LEFT));
    foreach ($columns as $column) $characters[$column] = '|';
    $item = $entry->event ?? $entry->record;
    $own = $columns[$item->process];
    if (isset($entry->record)) {
        $characters[$own] = '#';
        writeText($characters, $own + 1, $item->snapshot->name);
    } else {
        $symbols = ['LOCAL' => '*', 'NOFUNDS' => 'x', 'SEND' => 'S', 'BCAST' => 'B', 'RECV' => 'R'];
        $characters[$own] = $symbols[$item->type];
        if ($item->type === 'SEND' || $item->type === 'BCAST') writeText($characters, $own + 1, messageName($item->message));
        if ($item->type === 'RECV') {
            $source = $columns[$item->copy->source];
            $first = min($source, $own);
            $last = max($source, $own);
            for ($position = $first + 1; $position < $last; $position++) $characters[$position] = in_array($position, $columns, true) ? '+' : '-';
            $characters[$source < $own ? $last - 1 : $first + 1] = $source < $own ? '>' : '<';
            writeText($characters, $first + 2, messageName($item->message));
        }
    }
    return rtrim($characters);
}

function diagramReport($simulation) {
    $lines = [diagramHeader($simulation->names, 't')];
    foreach ($simulation->timeline as $entry) {
        $item = $entry->event ?? $entry->record;
        $lines[] = diagramLine($entry, $simulation->names, $item->time);
    }
    $lines[] = diagramHeader($simulation->names, 'L');
    $ordered = $simulation->events;
    usort($ordered, fn($a, $b) => ($a->L <=> $b->L) ?: ($a->process <=> $b->process));
    foreach ($ordered as $event) $lines[] = diagramLine((object)['event' => $event], $simulation->names, $event->L);
    return $lines;
}

function writeReport($filename, $lines) {
    file_put_contents('output/' . $filename, $lines ? implode("\n", $lines) . "\n" : '');
}

$topology = readTopology();
$programs = readPrograms($topology['names']);
$params = readParameters();
$simulation = (new Simulation($topology, $programs, $params, false))->run();
$raw = (new Simulation($topology, $programs, $params, true))->run();
writeReport('trace.txt', traceReport($simulation));
writeReport('deliveries.txt', deliveriesReport($simulation));
writeReport('snapshots.txt', snapshotsReport($simulation, $raw));
writeReport('analysis.txt', analysisReport($simulation, $raw));
writeReport('diagram.txt', diagramReport($simulation));
