<?php

function formatReal(?float $value, int $decimals = 4): string
{
    if ($value === null) {
        return '-';
    }
    $text = number_format($value, $decimals, '.', '');
    return (float) $text == 0.0 ? number_format(0.0, $decimals, '.', '') : $text;
}

function ratio(int $numerator, int $denominator): string
{
    if ($denominator === 0) {
        return '-';
    }
    $rounded = intdiv(20000 * $numerator + $denominator, 2 * $denominator);
    return intdiv($rounded, 10000) . '.' . str_pad((string) ($rounded % 10000), 4, '0', STR_PAD_LEFT);
}

function fraction(array $value): string
{
    [$numerator, $denominator] = $value;
    $a = $numerator;
    $b = $denominator;
    while ($b !== 0) {
        [$a, $b] = [$b, $a % $b];
    }
    return intdiv($numerator, $a) . '/' . intdiv($denominator, $a) . ' ' . ratio($numerator, $denominator);
}

function compareFractions(array $first, array $second): int
{
    return ($first[0] * $second[1]) <=> ($second[0] * $first[1]);
}

function confusion(array $probabilities, array $targets, float $threshold): object
{
    $result = (object) ['tp' => 0, 'fp' => 0, 'tn' => 0, 'fn' => 0, 'correct' => 0, 'predictions' => []];
    foreach ($probabilities as $row => $probability) {
        $predicted = (int) ($probability >= $threshold);
        $result->predictions[] = $predicted;
        if ($predicted === $targets[$row]) {
            $result->correct++;
        }
        if ($predicted === 1) {
            $key = $targets[$row] === 1 ? 'tp' : 'fp';
        } else {
            $key = $targets[$row] === 1 ? 'fn' : 'tn';
        }
        $result->$key++;
    }
    return $result;
}

function auc(array $scores, array $targets): array
{
    $order = range(0, count($scores) - 1);
    usort($order, fn($a, $b) => ($scores[$a] <=> $scores[$b]) ?: ($a <=> $b));
    $positives = $ranks = 0;
    for ($start = 0; $start < count($order);) {
        $end = $start + 1;
        while ($end < count($order) && $scores[$order[$end]] === $scores[$order[$start]]) {
            $end++;
        }
        $doubledRank = $start + 1 + $end;
        for ($position = $start; $position < $end; $position++) {
            if ($targets[$order[$position]] === 1) {
                $positives++;
                $ranks += $doubledRank;
            }
        }
        $start = $end;
    }
    return [$ranks - $positives * ($positives + 1), 2 * $positives * (count($scores) - $positives)];
}

function rocPoints(array $probabilities, array $targets): array
{
    $order = range(0, count($probabilities) - 1);
    usort($order, fn($a, $b) => ($probabilities[$b] <=> $probabilities[$a]) ?: ($a <=> $b));
    $points = [];
    $tp = $fp = 0;
    for ($start = 0; $start < count($order);) {
        $end = $start + 1;
        while ($end < count($order) && $probabilities[$order[$end]] === $probabilities[$order[$start]]) {
            $end++;
        }
        for ($position = $start; $position < $end; $position++) {
            if ($targets[$order[$position]] === 1) {
                $tp++;
            } else {
                $fp++;
            }
        }
        $points[] = (object) ['threshold' => $probabilities[$order[$start]], 'tp' => $tp, 'fp' => $fp];
        $start = $end;
    }
    return $points;
}
