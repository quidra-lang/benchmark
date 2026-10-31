<?php

namespace Bootstrap;

class Minstd
{
    public function __construct(public int $state)
    {
    }

    public function draw(): int
    {
        $this->state = 48271 * $this->state % 2147483647;
        return $this->state;
    }

    public function below(int $limit): int
    {
        return $this->draw() % $limit;
    }

    public function shuffle(array $values): array
    {
        for ($index = count($values) - 1; $index > 0; $index--) {
            $other = $this->below($index + 1);
            [$values[$index], $values[$other]] = [$values[$other], $values[$index]];
        }
        return $values;
    }
}
