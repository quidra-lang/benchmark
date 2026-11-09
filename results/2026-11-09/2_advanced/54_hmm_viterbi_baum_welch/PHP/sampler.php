<?php

class Minstd
{
    private $state;

    public function __construct($seed) { $this->state = $seed; }

    public function uniform()
    {
        $this->state = (48271 * $this->state) % 2147483647;
        return $this->state / 2147483647;
    }

    public function draw($weights)
    {
        $total = 0.0;
        foreach ($weights as $weight) $total += $weight;
        $threshold = $this->uniform() * $total;
        $cumulative = 0.0;
        foreach ($weights as $i => $weight) {
            $cumulative += $weight;
            if ($threshold < $cumulative) return $i;
        }
        return count($weights) - 1;
    }
}

function synthetic($model, $length, $generator)
{
    $path = [];
    $observations = [];
    for ($t = 0; $t < $length; $t++) {
        $weights = $t === 0 ? $model['initial'] : $model['transition'][$path[$t - 1]];
        $state = $generator->draw($weights);
        $path[] = $state;
        $observations[] = $generator->draw($model['emission'][$state]);
    }
    return compact('path', 'observations');
}

function posterior_path($model, $factors, $generator)
{
    $path = array_fill(0, count($factors), 0);
    $last = count($factors) - 1;
    $path[$last] = $generator->draw($factors[$last]);
    for ($t = $last - 1; $t >= 0; $t--) {
        $next = $path[$t + 1];
        $weights = [];
        foreach ($factors[$t] as $i => $value) $weights[] = $value * $model['transition'][$i][$next];
        $path[$t] = $generator->draw($weights);
    }
    return $path;
}
