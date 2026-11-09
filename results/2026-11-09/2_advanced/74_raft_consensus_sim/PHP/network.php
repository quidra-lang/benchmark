<?php

const TYPES = ['RV', 'RVR', 'AE', 'AER', 'TN'];

function newCounts(): object
{
    return (object) ['sent' => 0, 'delivered' => 0, 'inflight' => 0, 'partition' => 0, 'rule' => 0, 'loss' => 0, 'down' => 0];
}

function endpointMatches(string $pattern, int $number): bool { return $pattern === '*' || (int) $pattern === $number; }

class Network
{
    public array $groups;
    public array $queue = [];
    public int $serial = 0;
    public object $total;
    public array $types = [];
    public array $links = [];

    public function __construct(int $size, string $path)
    {
        $this->groups = array_fill(0, $size + 1, 0);
        $this->total = newCounts();
        foreach (TYPES as $type) $this->types[$type] = newCounts();
        $lines = array_map(fn($line) => explode(' ', $line), file($path, FILE_IGNORE_NEW_LINES));
        for ($source = 1; $source <= $size; $source++) for ($destination = 1; $destination <= $size; $destination++) {
            if ($source === $destination) continue;
            $link = (object) ['source' => $source, 'destination' => $destination, 'delay' => (int) $lines[0][1],
                'loss' => 0, 'pass' => 0, 'drops' => [], 'counts' => newCounts()];
            foreach (array_slice($lines, 1) as $fields) {
                [$kind, $a, $b] = $fields;
                $args = array_slice($fields, 3);
                if (!endpointMatches($a, $source) || !endpointMatches($b, $destination)) continue;
                if ($kind === 'DELAY') $link->delay = (int) $args[0];
                elseif ($kind === 'LOSS') $link->loss = (int) $args[0];
                else $link->drops[] = (object) ['type' => $args[0], 'first' => (int) $args[1], 'last' => (int) $args[2]];
            }
            $this->links[$source . '/' . $destination] = $link;
        }
    }

    public function separated(int $source, int $destination): bool { return $this->groups[$source] !== $this->groups[$destination]; }
    public function partition(array $groups): void { foreach ($groups as $index => $group) foreach ($group as $node) $this->groups[$node] = $index; }
    public function heal(): void { $this->groups = array_fill(0, count($this->groups), 0); }

    public function count(object $message, string $field, int $amount = 1): void
    {
        $this->total->$field += $amount;
        $this->types[$message->type]->$field += $amount;
        $this->links[$message->source . '/' . $message->destination]->counts->$field += $amount;
    }

    public function send(int $time, int $source, int $destination, string $type, int $term, array $content = []): void
    {
        $message = (object) compact('source', 'destination', 'type', 'term', 'content');
        $message->serial = $this->serial++;
        $link = $this->links[$source . '/' . $destination];
        $this->count($message, 'sent');
        if ($this->separated($source, $destination)) { $this->count($message, 'partition'); return; }
        foreach ($link->drops as $rule) if (($rule->type === $type || $rule->type === 'ALL') && $rule->first <= $time && $time <= $rule->last) {
            $this->count($message, 'rule'); return;
        }
        $link->pass++;
        if ($link->loss > 0 && $link->pass % $link->loss === 0) { $this->count($message, 'loss'); return; }
        $arrival = $time + $link->delay;
        $this->queue[$arrival][] = $message;
        $this->count($message, 'inflight');
    }

    public function take(int $time): array
    {
        $messages = $this->queue[$time] ?? [];
        unset($this->queue[$time]);
        usort($messages, fn($a, $b) => ($a->source <=> $b->source) ?: ($a->serial <=> $b->serial));
        return $messages;
    }

    public function resolve(object $message, string $outcome): void
    {
        $this->count($message, 'inflight', -1);
        $this->count($message, $outcome);
    }
}
