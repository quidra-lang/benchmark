<?php

function kernel(string $name, float $u): float
{
    $t = 1 - $u * $u;
    if ($name === 'epanechnikov') {
        return 0.75 * $t;
    }
    if ($name === 'biweight') {
        return 0.9375 * $t * $t;
    }
    return 1.09375 * $t * $t * $t;
}

function kernelEstimate(array $points, string $kind, string $name, int $bandwidth, int $position): object
{
    $constants = ['epanechnikov' => 0.75, 'biweight' => 0.9375, 'triweight' => 1.09375];
    $x0 = $position / 100;
    $h = $bandwidth / 100;
    $used = [];
    $s0 = $s1 = $s2 = $t0 = $t1 = 0.0;
    foreach ($points as $j => $point) {
        if (abs($point->X - $position) >= $bandwidth) {
            continue;
        }
        $d = $point->x - $x0;
        $weight = kernel($name, $d / $h);
        $used[] = (object) ['index' => $j, 'd' => $d, 'weight' => $weight];
        $s0 += $weight;
        $t0 += $weight * $point->y;
        if ($kind === 'll') {
            $s1 += $weight * $d;
            $s2 += $weight * $d * $d;
            $t1 += $weight * $d * $point->y;
        }
    }
    if (count($used) < ($kind === 'nw' ? 1 : 2)) {
        return (object) ['value' => null, 'weights' => null, 'diagonal' => null];
    }
    $weights = array_fill(0, count($points), 0.0);
    if ($kind === 'nw') {
        foreach ($used as $point) {
            $weights[$point->index] = $point->weight / $s0;
        }
        return (object) ['value' => $t0 / $s0, 'weights' => $weights, 'diagonal' => $constants[$name] / $s0];
    }
    $q = $s0 * $s2 - $s1 * $s1;
    foreach ($used as $point) {
        $weights[$point->index] = $point->weight * ($s2 - $s1 * $point->d) / $q;
    }
    return (object) ['value' => ($s2 * $t0 - $s1 * $t1) / $q, 'weights' => $weights, 'diagonal' => $constants[$name] * $s2 / $q];
}

function fitKernel(array $points, string $kind, string $name, int $bandwidth): object
{
    $at = fn($position) => kernelEstimate($points, $kind, $name, $bandwidth, $position);
    $estimates = array_map(fn($point) => $at($point->X), $points);
    foreach ($estimates as $item) {
        if ($item->value === null) {
            return (object) ['yhat' => null, 'lev' => null, 'edf' => null, 'at' => $at];
        }
    }
    $lev = array_map(fn($item) => $item->diagonal, $estimates);
    $edf = 0.0;
    foreach ($lev as $value) {
        $edf += $value;
    }
    return (object) ['yhat' => array_map(fn($item) => $item->value, $estimates), 'lev' => $lev, 'edf' => $edf, 'at' => $at];
}
