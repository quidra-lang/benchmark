<?php

function orderedSum(array $values): float
{
    $total = 0.0;
    foreach ($values as $value) {
        $total += $value;
    }
    return $total;
}

function mean(array $values): float
{
    return orderedSum($values) / count($values);
}

function sampleVariance(array $values): float
{
    $average = mean($values);
    $total = 0.0;
    foreach ($values as $value) {
        $difference = $value - $average;
        $total += $difference * $difference;
    }
    return $total / (count($values) - 1);
}

function decompose(array $values, int $season): object
{
    $half = intdiv($season, 2);
    $trend = $residualAdd = $residualMult = array_fill(0, count($values), null);
    $defined = [];
    $add = $mult = array_fill(0, $season, 0.0);
    $counts = array_fill(0, $season, 0);
    for ($t = $half; $t < count($values) - $half; $t++) {
        $total = 0.5 * $values[$t - $half];
        for ($i = $t - $half + 1; $i < $t + $half; $i++) {
            $total += $values[$i];
        }
        $total += 0.5 * $values[$t + $half];
        $trend[$t] = $total / $season;
        $defined[] = $t;
        $add[$t % $season] += $values[$t] - $trend[$t];
        $mult[$t % $season] += $values[$t] / $trend[$t];
        $counts[$t % $season]++;
    }
    for ($j = 0; $j < $season; $j++) {
        $add[$j] /= $counts[$j];
        $mult[$j] /= $counts[$j];
    }
    $addMean = mean($add);
    $multMean = mean($mult);
    for ($j = 0; $j < $season; $j++) {
        $add[$j] -= $addMean;
        $mult[$j] /= $multMean;
    }
    foreach ($defined as $t) {
        $residualAdd[$t] = $values[$t] - $trend[$t] - $add[$t % $season];
        $residualMult[$t] = $values[$t] / ($trend[$t] * $mult[$t % $season]);
    }
    return (object) compact('trend', 'defined', 'add', 'mult', 'residualAdd', 'residualMult');
}

function regression(array $values): object
{
    $center = (count($values) + 1) / 2.0;
    $average = mean($values);
    $numerator = $denominator = 0.0;
    foreach ($values as $t => $value) {
        $difference = $t + 1 - $center;
        $numerator += $difference * ($value - $average);
        $denominator += $difference * $difference;
    }
    $slope = $numerator / $denominator;
    return (object) ['intercept' => $average - $slope * $center, 'slope' => $slope];
}
