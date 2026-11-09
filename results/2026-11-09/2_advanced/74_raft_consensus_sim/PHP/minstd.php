<?php

class Minstd
{
    public int $state;
    public int $draws = 0;
    public function __construct(int $seed) { $this->state = $seed; }
    public function next(): int
    {
        $this->state = (48271 * $this->state) % 2147483647;
        $this->draws++;
        return $this->state;
    }
    public function range(int $low, int $high): int { return $low + $this->next() % ($high - $low + 1); }
}
