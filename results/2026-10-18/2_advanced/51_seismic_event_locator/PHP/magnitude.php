<?php

function seismicLog10(float $value): float
{
    return log($value) / 2.302585092994046;
}

function median(array $values): ?float
{
    if (!$values) {
        return null;
    }
    sort($values, SORT_NUMERIC);
    $middle = intdiv(count($values), 2);
    return count($values) % 2 === 1 ? (float) $values[$middle] : ($values[$middle - 1] + $values[$middle]) / 2;
}

function localMagnitude(int $amplitude, float $distanceKm, array $coefficients): float
{
    [$a, $b, $c] = $coefficients;
    return seismicLog10($amplitude) + $a * seismicLog10($distanceKm / 100) + $b * ($distanceKm - 100) + $c;
}

function durationMagnitude(int $duration, float $distanceKm, array $coefficients): float
{
    [$a, $b, $c] = $coefficients;
    return $a + $b * seismicLog10($duration / 100) + $c * $distanceKm;
}

function magnitudeClass(int $hundredths): int
{
    $value = $hundredths + 5;
    return $value >= 0 ? intdiv($value, 10) : -intdiv(-$value + 9, 10);
}

function frequencyStatistics(array $classes): object
{
    $frequencies = [];
    foreach ($classes as $value) {
        $frequencies[$value] = ($frequencies[$value] ?? 0) + 1;
    }
    $ordered = array_keys($frequencies);
    sort($ordered, SORT_NUMERIC);
    $completeness = $ordered[0];
    foreach ($ordered as $value) {
        if ($frequencies[$value] > $frequencies[$completeness]) {
            $completeness = $value;
        }
    }
    $count = 0;
    $total = 0;
    foreach ($classes as $value) {
        if ($value >= $completeness) {
            $count++;
            $total += $value;
        }
    }
    $mc = $completeness / 10;
    $mean = $total / (10 * $count);
    $b = 0.4342944819032518 / ($mean - ($mc - 0.05));
    return (object) ['frequencies' => $frequencies, 'minimum' => $ordered[0], 'maximum' => end($ordered),
        'completeness' => $completeness, 'count' => $count, 'b' => $b, 'sigma' => $b / sqrt($count),
        'a' => seismicLog10($count) + $b * $mc];
}
