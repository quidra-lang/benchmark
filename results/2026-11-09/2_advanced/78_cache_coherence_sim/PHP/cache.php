<?php

class Cache
{
    public array $entries;
    public array $fills;
    public array $evictions;
    private array $times;
    private array $bits;
    private int $clock = 0;
    public int $setCount;
    public int $ways;
    public string $policy;

    public function __construct(array $geometry, string $policy)
    {
        $this->setCount = $geometry['sets'];
        $this->ways = $geometry['ways'];
        $this->policy = $policy;
        $this->entries = array_fill(0, $this->setCount, array_fill(0, $this->ways, null));
        $this->times = array_fill(0, $this->setCount, array_fill(0, $this->ways, 0));
        $this->bits = array_fill(0, $this->setCount, array_fill(0, $this->ways, 0));
        $this->fills = $this->evictions = array_fill(0, $this->setCount, 0);
    }

    public function locate(int $block): ?array
    {
        $row = $block % $this->setCount;
        foreach ($this->entries[$row] as $way => $entry) {
            if ($entry !== null && $entry['block'] === $block) return [$row, $way];
        }
        return null;
    }

    public function state(int $block): string
    {
        $place = $this->locate($block);
        return $place === null ? 'I' : $this->entries[$place[0]][$place[1]]['state'];
    }

    public function setState(int $block, string $state): void
    {
        $place = $this->locate($block);
        if ($place !== null) $this->entries[$place[0]][$place[1]]['state'] = $state;
    }

    private function touchWay(int $row, int $way, bool $fill): void
    {
        if ($this->policy === 'LRU' || ($this->policy === 'FIFO' && $fill)) {
            $this->times[$row][$way] = ++$this->clock;
        } elseif ($this->policy === 'PLRU') {
            $lo = 0;
            $hi = $this->ways;
            $node = 1;
            while ($hi - $lo > 1) {
                $mid = intdiv($lo + $hi, 2);
                if ($way < $mid) {
                    $this->bits[$row][$node] = 1;
                    $hi = $mid;
                    $node *= 2;
                } else {
                    $this->bits[$row][$node] = 0;
                    $lo = $mid;
                    $node = 2 * $node + 1;
                }
            }
        }
    }

    public function touch(int $block): void
    {
        $place = $this->locate($block);
        if ($place !== null) $this->touchWay($place[0], $place[1], false);
    }

    private function victim(int $row): int
    {
        if ($this->policy === 'PLRU') {
            $lo = 0;
            $hi = $this->ways;
            $node = 1;
            while ($hi - $lo > 1) {
                $mid = intdiv($lo + $hi, 2);
                if ($this->bits[$row][$node] === 0) {
                    $hi = $mid;
                    $node *= 2;
                } else {
                    $lo = $mid;
                    $node = 2 * $node + 1;
                }
            }
            return $lo;
        }
        $best = 0;
        for ($way = 1; $way < $this->ways; $way++) {
            if ($this->times[$row][$way] < $this->times[$row][$best]) $best = $way;
        }
        return $best;
    }

    public function fill(int $block, string $state): ?array
    {
        $row = $block % $this->setCount;
        $way = null;
        foreach ($this->entries[$row] as $index => $entry) {
            if ($entry === null) {
                $way = $index;
                break;
            }
        }
        if ($way === null) $way = $this->victim($row);
        $old = $this->entries[$row][$way];
        if ($old !== null) $this->evictions[$row]++;
        $this->entries[$row][$way] = ['block' => $block, 'state' => $state];
        $this->fills[$row]++;
        $this->touchWay($row, $way, true);
        return $old;
    }

    public function remove(int $block): ?array
    {
        $place = $this->locate($block);
        if ($place === null) return null;
        $entry = $this->entries[$place[0]][$place[1]];
        $this->entries[$place[0]][$place[1]] = null;
        return $entry;
    }

    public function order(int $row): string
    {
        if ($this->policy === 'PLRU') {
            return $this->ways === 1 ? '-' : implode('', array_slice($this->bits[$row], 1));
        }
        $active = [];
        foreach ($this->entries[$row] as $way => $entry) if ($entry !== null) $active[] = $way;
        usort($active, fn($a, $b) => ($this->times[$row][$b] <=> $this->times[$row][$a]) ?: ($a <=> $b));
        return $active ? implode(' ', $active) : '-';
    }
}
