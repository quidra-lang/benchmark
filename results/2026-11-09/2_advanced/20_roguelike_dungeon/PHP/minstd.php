<?php
declare(strict_types=1);

namespace Roguelike;

final class Minstd
{
    public function __construct(public int $state) {}
    public function draw(): int { return $this->state = $this->state * 48271 % 2147483647; }
    public function rnd(int $n): int { return $this->draw() % $n; }

    public function roll(int $count, int $sides): int
    {
        $total = 0;
        for ($index = 0; $index < $count; $index++) {
            $total += 1 + $this->rnd($sides);
        }
        return $total;
    }

    public function select(array $weights): int
    {
        $q = $this->draw() % array_sum($weights);
        $total = 0;
        foreach ($weights as $index => $weight) {
            $total += $weight;
            if ($q < $total) {
                return $index;
            }
        }
        return count($weights) - 1;
    }
}
