<?php

function median(array $values): float
{
    sort($values, SORT_NUMERIC);
    $middle = intdiv(count($values), 2);
    return count($values) % 2 === 1 ? $values[$middle] : ($values[$middle - 1] + $values[$middle]) / 2;
}

function cholesky(array $matrix): array
{
    $size = count($matrix);
    $lower = array_fill(0, $size, array_fill(0, $size, 0.0));
    for ($k = 0; $k < $size; $k++) {
        for ($l = 0; $l <= $k; $l++) {
            $sigma = $matrix[$k][$l];
            for ($i = 0; $i < $l; $i++) {
                $sigma -= $lower[$k][$i] * $lower[$l][$i];
            }
            $lower[$k][$l] = $l === $k ? sqrt($sigma) : $sigma / $lower[$l][$l];
        }
    }
    return $lower;
}

function solve(array $lower, array $right): array
{
    $eta = [];
    foreach ($right as $k => $initial) {
        $value = $initial;
        for ($j = 0; $j < $k; $j++) {
            $value -= $lower[$k][$j] * $eta[$j];
        }
        $eta[] = $value / $lower[$k][$k];
    }
    $result = array_fill(0, count($right), 0.0);
    for ($k = count($right) - 1; $k >= 0; $k--) {
        $value = $eta[$k];
        for ($j = $k + 1; $j < count($right); $j++) {
            $value -= $lower[$j][$k] * $result[$j];
        }
        $result[$k] = $value / $lower[$k][$k];
    }
    return $result;
}

function localFit(array $points, int $degree, int $span, array $robustness, int $position): object
{
    $count = intdiv($span * count($points), 100);
    $neighbours = array_keys($points);
    usort($neighbours, fn($a, $b) => (abs($points[$a]->X - $position) <=> abs($points[$b]->X - $position)) ?: ($a <=> $b));
    $neighbours = array_slice($neighbours, 0, $count);
    $extent = abs($points[$neighbours[count($neighbours) - 1]]->X - $position);
    sort($neighbours, SORT_NUMERIC);
    $x0 = $position / 100;
    $local = [];
    foreach ($neighbours as $index) {
        $distance = abs($points[$index]->X - $position) / $extent;
        $s = 1 - $distance * $distance * $distance;
        $weight = $s * $s * $s;
        $d = $points[$index]->x - $x0;
        $local[] = (object) ['index' => $index, 'weight' => $weight * $robustness[$index],
            'basis' => $degree === 1 ? [1, $d] : [1, $d, $d * $d]];
    }
    $matrix = array_fill(0, $degree + 1, array_fill(0, $degree + 1, 0.0));
    $right = array_fill(0, $degree + 1, 0.0);
    foreach ($local as $point) {
        for ($k = 0; $k <= $degree; $k++) {
            for ($l = 0; $l <= $degree; $l++) {
                $matrix[$k][$l] += $point->weight * $point->basis[$k] * $point->basis[$l];
            }
            $right[$k] += $point->weight * $point->basis[$k] * $points[$point->index]->y;
        }
    }
    $lower = cholesky($matrix);
    $beta = solve($lower, $right);
    $unit = array_fill(0, $degree + 1, 0.0);
    $unit[0] = 1;
    $zeta = solve($lower, $unit);
    $weights = array_fill(0, count($points), 0.0);
    foreach ($local as $point) {
        $total = 0.0;
        for ($k = 0; $k <= $degree; $k++) {
            $total += $zeta[$k] * $point->basis[$k];
        }
        $weights[$point->index] = $point->weight * $total;
    }
    return (object) ['value' => $beta[0], 'weights' => $weights, 'zeta0' => $zeta[0]];
}

function fitLoess(array $points, int $degree, int $span, int $iterations): object
{
    $robustness = array_fill(0, count($points), 1);
    $estimates = array_map(fn($point) => localFit($points, $degree, $span, $robustness, $point->X), $points);
    $records = [];
    for ($iteration = 1; $iteration <= $iterations; $iteration++) {
        $residuals = [];
        foreach ($points as $i => $point) {
            $residuals[] = $point->y - $estimates[$i]->value;
        }
        $scale = median(array_map('abs', $residuals));
        $robustness = [];
        foreach ($residuals as $error) {
            $u = $error / (6 * $scale);
            if (abs($u) >= 1) {
                $robustness[] = 0.0;
            } else {
                $value = 1 - $u * $u;
                $robustness[] = $value * $value;
            }
        }
        $next = array_map(fn($point) => localFit($points, $degree, $span, $robustness, $point->X), $points);
        $change = 0.0;
        foreach ($next as $i => $estimate) {
            $change = max($change, abs($estimate->value - $estimates[$i]->value));
        }
        $zeros = count(array_filter($robustness, fn($value) => $value == 0));
        $records[] = (object) compact('iteration', 'scale', 'zeros', 'change');
        $estimates = $next;
    }
    $lev = [];
    $edf = 0.0;
    foreach ($estimates as $i => $estimate) {
        $lev[] = $robustness[$i] * $estimate->zeta0;
        $edf += $lev[$i];
    }
    return (object) ['yhat' => array_map(fn($estimate) => $estimate->value, $estimates), 'lev' => $lev, 'edf' => $edf,
        'robustness' => $robustness, 'records' => $records,
        'at' => fn($position) => localFit($points, $degree, $span, $robustness, $position)];
}
