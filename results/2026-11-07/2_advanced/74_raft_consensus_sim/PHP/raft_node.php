<?php

function makeEntry(int $term, string $command, int $request): object { return (object) compact('term', 'command', 'request'); }
function copyEntry(object $entry): object { return clone $entry; }
function sameEntry(object $a, object $b): bool { return $a->term === $b->term && $a->command === $b->command && $a->request === $b->request; }

class RaftNode
{
    public int $number;
    public int $currentTerm = 0;
    public ?int $votedFor = null;
    public array $log = [];
    public bool $up = true;
    public object $stats;
    public string $role;
    public int $commit;
    public int $applied;
    public array $store;
    public ?int $knownLeader;
    public array $votes;
    public ?int $electionDeadline;
    public array $next;
    public array $match;
    public ?int $heartbeatDeadline;
    public ?int $quorumDeadline;
    public array $heard;
    public ?object $transfer;
    public ?object $election;

    public function __construct(int $number)
    {
        $this->number = $number;
        $this->stats = (object) ['elections' => 0, 'leaders' => 0, 'votesGranted' => 0, 'leaderTicks' => 0,
            'aeOk' => 0, 'aeFail' => 0, 'appended' => 0, 'truncated' => 0, 'applies' => 0];
        $this->resetVolatile();
    }

    public function resetVolatile(): void
    {
        $this->role = 'FOLLOWER'; $this->commit = $this->applied = 0; $this->store = [];
        $this->knownLeader = null; $this->votes = []; $this->electionDeadline = null;
        $this->next = $this->match = []; $this->heartbeatDeadline = $this->quorumDeadline = null;
        $this->heard = []; $this->transfer = $this->election = null;
    }

    public function lastIndex(): int { return count($this->log); }
    public function lastTerm(): int { return $this->term($this->lastIndex()); }
    public function entry(int $index): object { return $this->log[$index - 1]; }
    public function term(int $index): int { return $index === 0 ? 0 : $this->entry($index)->term; }
    public function candidateCurrent(int $lastIndex, int $lastTerm): bool
    {
        return $lastTerm > $this->lastTerm() || ($lastTerm === $this->lastTerm() && $lastIndex >= $this->lastIndex());
    }
}

function applyCommand(array &$store, string $command): ?string
{
    $parts = explode(' ', $command);
    $kind = $parts[0];
    if ($kind === 'NOOP') return null;
    $key = $parts[1];
    if ($kind === 'SET') { $store[$key] = (int) $parts[2]; return 'ok'; }
    if ($kind === 'ADD') {
        $sum = ($store[$key] ?? 0) + (int) $parts[2];
        $store[$key] = $sum;
        return (string) $sum;
    }
    if ($kind === 'DEL') {
        if (!array_key_exists($key, $store)) return 'missing';
        unset($store[$key]);
        return 'deleted';
    }
    return array_key_exists($key, $store) ? (string) $store[$key] : 'missing';
}
