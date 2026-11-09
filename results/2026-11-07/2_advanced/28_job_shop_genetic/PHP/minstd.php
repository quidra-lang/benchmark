<?php

class Minstd
{
    public function __construct(private int $state) {}

    public function draw(): int
    {
        $this->state = (48271 * $this->state) % 2147483647;
        return $this->state;
    }

    public function below(int $limit): int
    {
        return $this->draw() % $limit;
    }

    public function chance(array $probability): bool
    {
        return $this->below($probability[1]) < $probability[0];
    }

    public function shuffled(array $sequence): array
    {
        for ($i = count($sequence) - 1; $i >= 1; $i--) {
            $j = $this->below($i + 1);
            [$sequence[$i], $sequence[$j]] = [$sequence[$j], $sequence[$i]];
        }
        return $sequence;
    }
}
