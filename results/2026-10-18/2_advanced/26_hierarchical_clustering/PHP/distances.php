<?php

const DISTANCE_TYPES = ['euclidean', 'manhattan', 'correlation'];

function sequentialSum(array $values): float
{
    $total = 0.0;
    foreach ($values as $value) {
        $total += $value;
    }
    return $total;
}

function squaredDistance(array $first, array $second): float
{
    $total = 0.0;
    foreach ($first as $f => $value) {
        $difference = $value - $second[$f];
        $total += $difference * $difference;
    }
    return $total;
}

function featureStatistics(array $rows): array
{
    $means = [];
    $deviations = [];
    for ($f = 0; $f < count($rows[0]); ++$f) {
        $column = array_column($rows, $f);
        $mean = sequentialSum($column) / count($rows);
        $variance = sequentialSum(array_map(fn($value) => ($value - $mean) * ($value - $mean), $column)) / (count($rows) - 1);
        $means[] = $mean;
        $deviations[] = sqrt($variance);
    }
    return [$means, $deviations];
}

function standardize(array $rows, array $means, array $deviations): array
{
    return array_map(function ($row) use ($means, $deviations) {
        $values = [];
        foreach ($row as $f => $value) {
            $values[] = ($value - $means[$f]) / $deviations[$f];
        }
        return $values;
    }, $rows);
}

function vectorDistance(array $first, array $second, string $kind): float
{
    if ($kind === 'euclidean') {
        return sqrt(squaredDistance($first, $second));
    }
    if ($kind === 'manhattan') {
        $total = 0.0;
        foreach ($first as $f => $value) {
            $total += abs($value - $second[$f]);
        }
        return $total;
    }
    $meanFirst = sequentialSum($first) / count($first);
    $meanSecond = sequentialSum($second) / count($second);
    $cross = $spreadFirst = $spreadSecond = 0.0;
    foreach ($first as $f => $value) {
        $a = $value - $meanFirst;
        $b = $second[$f] - $meanSecond;
        $cross += $a * $b;
        $spreadFirst += $a * $a;
        $spreadSecond += $b * $b;
    }
    return 1 - $cross / sqrt($spreadFirst * $spreadSecond);
}

function distanceMatrix(array $vectors, string $kind): array
{
    $count = count($vectors);
    $matrix = array_fill(0, $count, array_fill(0, $count, 0.0));
    for ($i = 0; $i < $count; ++$i) {
        for ($j = $i + 1; $j < $count; ++$j) {
            $value = vectorDistance($vectors[$i], $vectors[$j], $kind);
            $matrix[$i][$j] = $matrix[$j][$i] = $value;
        }
    }
    return $matrix;
}
