<?php

class SmoothingSpline
{
    private array $positions;
    private array $x;
    private float $lambda;
    private array $h = [];
    private array $lower1 = [];
    private array $lower2 = [];
    private array $diagonal = [];

    public function __construct(array $points, float $lambda)
    {
        $this->positions = array_map(fn($point) => $point->X, $points);
        $this->x = array_map(fn($point) => $point->x, $points);
        $this->lambda = $lambda;
        for ($i = 1; $i < count($this->x); $i++) {
            $this->h[] = $this->x[$i] - $this->x[$i - 1];
        }
        $count = count($points) - 2;
        $a = $b = $c = $diagonal = $first = $second = [];
        for ($k = 0; $k < $count; $k++) {
            $a[] = 1 / $this->h[$k];
            $c[] = 1 / $this->h[$k + 1];
            $b[] = -($a[$k] + $c[$k]);
            $diagonal[] = ($this->h[$k] + $this->h[$k + 1]) / 3 + $lambda * ($a[$k] * $a[$k] + $b[$k] * $b[$k] + $c[$k] * $c[$k]);
        }
        for ($k = 0; $k < $count - 1; $k++) {
            $first[] = $this->h[$k + 1] / 6 + $lambda * $c[$k] * ($b[$k] + $b[$k + 1]);
        }
        for ($k = 0; $k < $count - 2; $k++) {
            $second[] = $lambda * $c[$k] * $c[$k + 1];
        }
        for ($k = 0; $k < $count; $k++) {
            $d1 = $this->diagonal[$k - 1] ?? 0;
            $d2 = $this->diagonal[$k - 2] ?? 0;
            $l2 = $k >= 2 ? $second[$k - 2] / $d2 : 0;
            $l1 = $k >= 1 ? ($first[$k - 1] - $l2 * $d2 * $this->lower1[$k - 1]) / $d1 : 0;
            $this->lower1[] = $l1;
            $this->lower2[] = $l2;
            $this->diagonal[] = $diagonal[$k] - $l1 * $l1 * $d1 - $l2 * $l2 * $d2;
        }
    }

    public function fit(array $values): object
    {
        $z = [];
        for ($k = 0; $k < count($values) - 2; $k++) {
            $phi = ($values[$k + 2] - $values[$k + 1]) / $this->h[$k + 1] - ($values[$k + 1] - $values[$k]) / $this->h[$k];
            $z[] = $phi - $this->lower1[$k] * ($z[$k - 1] ?? 0) - $this->lower2[$k] * ($z[$k - 2] ?? 0);
        }
        $gamma = array_fill(0, count($values), 0.0);
        for ($k = count($z) - 1; $k >= 0; $k--) {
            $gamma[$k + 1] = $z[$k] / $this->diagonal[$k] - ($this->lower1[$k + 1] ?? 0) * $gamma[$k + 2]
                - ($this->lower2[$k + 2] ?? 0) * ($gamma[$k + 3] ?? 0);
        }
        $g = [];
        foreach ($values as $i => $value) {
            if ($i === 0) {
                $omega = ($gamma[1] - $gamma[0]) / $this->h[0];
            } elseif ($i === count($values) - 1) {
                $omega = 0 - ($gamma[$i] - $gamma[$i - 1]) / $this->h[$i - 1];
            } else {
                $omega = ($gamma[$i + 1] - $gamma[$i]) / $this->h[$i] - ($gamma[$i] - $gamma[$i - 1]) / $this->h[$i - 1];
            }
            $g[] = $value - $this->lambda * $omega;
        }
        return (object) compact('g', 'gamma');
    }

    public function evaluate(object $curve, int $position): float
    {
        $g = $curve->g;
        $gamma = $curve->gamma;
        $value = $position / 100;
        $last = count($this->x) - 1;
        if ($position < $this->positions[0]) {
            $slope = ($g[1] - $g[0]) / $this->h[0] - $this->h[0] * $gamma[1] / 6;
            return $g[0] - ($this->x[0] - $value) * $slope;
        }
        if ($position > $this->positions[$last]) {
            $slope = ($g[$last] - $g[$last - 1]) / $this->h[$last - 1] + $this->h[$last - 1] * $gamma[$last - 1] / 6;
            return $g[$last] + ($value - $this->x[$last]) * $slope;
        }
        $low = 0;
        $high = count($this->positions);
        while ($low < $high) {
            $middle = intdiv($low + $high, 2);
            if ($this->positions[$middle] < $position) {
                $low = $middle + 1;
            } else {
                $high = $middle;
            }
        }
        if ($this->positions[$low] === $position) {
            return $g[$low];
        }
        $i = $low - 1;
        $pl = $value - $this->x[$i];
        $pr = $this->x[$i + 1] - $value;
        return ($pl * $g[$i + 1] + $pr * $g[$i]) / $this->h[$i]
            - $pl * $pr * ((1 + $pl / $this->h[$i]) * $gamma[$i + 1] + (1 + $pr / $this->h[$i]) * $gamma[$i]) / 6;
    }

    public function unitFits(): array
    {
        $fits = [];
        foreach ($this->positions as $index => $position) {
            $values = array_fill(0, count($this->positions), 0.0);
            $values[$index] = 1.0;
            $fits[] = $this->fit($values);
        }
        return $fits;
    }
}

function fitSpline(array $points, float $lambda, bool $withWeights = true): object
{
    $system = new SmoothingSpline($points, $lambda);
    $curve = $system->fit(array_map(fn($point) => $point->y, $points));
    $units = $withWeights ? $system->unitFits() : null;
    $lev = null;
    $edf = null;
    if ($units !== null) {
        $lev = [];
        $edf = 0.0;
        foreach ($units as $i => $unit) {
            $lev[] = $unit->g[$i];
            $edf += $unit->g[$i];
        }
    }
    $at = function ($position) use ($system, $curve, $units) {
        return (object) ['value' => $system->evaluate($curve, $position), 'weights' => $units === null ? null
            : array_map(fn($unit) => $system->evaluate($unit, $position), $units)];
    };
    return (object) ['system' => $system, 'curve' => $curve, 'yhat' => $curve->g, 'lev' => $lev, 'edf' => $edf, 'at' => $at];
}
