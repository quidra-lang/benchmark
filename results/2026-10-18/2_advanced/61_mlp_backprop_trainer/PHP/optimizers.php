<?php

class Optimizer
{
    private object $run;
    private array $velocity;
    private array $first;
    private array $second;
    private float $pi1 = 1.0;
    private float $pi2 = 1.0;

    public function __construct(object $run, int $parameterCount)
    {
        $this->run = $run;
        $this->velocity = array_fill(0, $parameterCount, 0.0);
        $this->first = array_fill(0, $parameterCount, 0.0);
        $this->second = array_fill(0, $parameterCount, 0.0);
    }

    public function update(array &$theta, array $gradient, float $rate): void
    {
        $run = $this->run;
        if ($run->optimizer === 'ADAM') {
            $this->pi1 *= $run->beta1;
            $this->pi2 *= $run->beta2;
        }
        foreach ($gradient as $p => $value) {
            if ($run->optimizer === 'SGD') {
                $theta[$p] -= $rate * $value;
            } elseif ($run->optimizer === 'MOMENTUM') {
                $this->velocity[$p] = $run->mu * $this->velocity[$p] + $value;
                $theta[$p] -= $rate * $this->velocity[$p];
            } else {
                $this->first[$p] = $run->beta1 * $this->first[$p] + (1 - $run->beta1) * $value;
                $this->second[$p] = $run->beta2 * $this->second[$p] + (1 - $run->beta2) * $value * $value;
                $first = $this->first[$p] / (1 - $this->pi1);
                $second = $this->second[$p] / (1 - $this->pi2);
                $theta[$p] -= $rate * $first / (sqrt($second) + $run->epsilon);
            }
        }
    }
}

function learningRate(object $run, object $settings, int $epoch): float
{
    $rate = $run->eta;
    $steps = intdiv($epoch - 1, $settings->step);
    for ($step = 0; $step < $steps; $step++) {
        $rate *= $settings->gamma;
    }
    return $rate;
}
