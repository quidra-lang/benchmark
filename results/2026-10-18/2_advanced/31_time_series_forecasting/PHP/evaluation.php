<?php

function seasonalScale(array $values, int $season): float
{
    $total = 0.0;
    for ($t = $season; $t < count($values); $t++) {
        $total += abs($values[$t] - $values[$t - $season]);
    }
    return $total / (count($values) - $season);
}

function accuracy(array $actual, array $forecast, float $delta): object
{
    $errors = $absolute = $squares = $percentage = $symmetric = 0.0;
    foreach ($actual as $i => $value) {
        $error = $value - $forecast[$i];
        $magnitude = abs($error);
        $errors += $error;
        $absolute += $magnitude;
        $squares += $error * $error;
        $percentage += $magnitude / $value;
        $symmetric += 2.0 * $magnitude / (abs($value) + abs($forecast[$i]));
    }
    $count = count($actual);
    $mae = $absolute / $count;
    return (object) ['me' => $errors / $count, 'mae' => $mae, 'rmse' => sqrt($squares / $count),
        'mape' => 100.0 * $percentage / $count, 'smape' => 100.0 * $symmetric / $count, 'mase' => $mae / $delta];
}

function winkler(float $actual, float $low, float $high, int $coefficient): float
{
    if ($actual < $low) {
        return $high - $low + $coefficient * ($low - $actual);
    }
    if ($actual > $high) {
        return $high - $low + $coefficient * ($actual - $high);
    }
    return $high - $low;
}

function rankedIndices(array $values): array
{
    $order = range(0, count($values) - 1);
    usort($order, fn($a, $b) => ($values[$a] <=> $values[$b]) ?: ($a <=> $b));
    return $order;
}
