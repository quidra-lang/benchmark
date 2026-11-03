<?php
declare(strict_types=1);

namespace TimezoneRules;

final class Period
{
    public function __construct(public int $start, public int $offset, public bool $dst, public string $abbreviation) {}
    public function state(): array { return [$this->offset, $this->dst, $this->abbreviation]; }
}

final class Timeline
{
    public function __construct(public array $periods) {}

    public function indexAt(int $time): int
    {
        $low = 0;
        $high = count($this->periods);
        while ($low < $high) {
            $middle = intdiv($low + $high, 2);
            if ($this->periods[$middle]->start <= $time) {
                $low = $middle + 1;
            } else {
                $high = $middle;
            }
        }
        return $low - 1;
    }

    public function periodAt(int $time): Period { return $this->periods[$this->indexAt($time)]; }
    public function endOf(int $index): int { return isset($this->periods[$index + 1]) ? $this->periods[$index + 1]->start : POS_INFINITY; }
    public function nearby(int $firstLocal, int $lastLocal): array { return [$this->indexAt($firstLocal - 57600), $this->indexAt($lastLocal + 57600)]; }

    public function candidates(int $local): array
    {
        $found = [];
        [$first, $last] = $this->nearby($local, $local);
        for ($index = $first; $index <= $last; $index++) {
            $time = $local - $this->periods[$index]->offset;
            if ($this->periods[$index]->start <= $time && $time < $this->endOf($index)) {
                $found[] = $index;
            }
        }
        return $found;
    }

    public function skippingTransition(int $local): ?int
    {
        [$first, $last] = $this->nearby($local, $local);
        for ($index = max(1, $first); $index <= $last; $index++) {
            $start = $this->periods[$index]->start;
            if ($start + $this->periods[$index - 1]->offset <= $local && $local < $start + $this->periods[$index]->offset) {
                return $index;
            }
        }
        return null;
    }
}
