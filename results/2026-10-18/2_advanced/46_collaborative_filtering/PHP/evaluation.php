<?php

function clip(float $value): float
{
    return $value < 1 ? 1.0 : ($value > 5 ? 5.0 : $value);
}

function errorMetrics(array $errors): object
{
    if (count($errors) === 0) {
        return (object) ['rmse' => null, 'mae' => null];
    }
    $squared = 0.0;
    $absolute = 0.0;
    foreach ($errors as $error) {
        $squared += $error * $error;
        $absolute += abs($error);
    }
    return (object) ['rmse' => sqrt($squared / count($errors)), 'mae' => $absolute / count($errors)];
}

function trainingRmse(array $ratings, callable $predict): float
{
    $squared = 0.0;
    foreach ($ratings as $row) {
        $error = $row->rating - $predict($row->u, $row->i);
        $squared += $error * $error;
    }
    return sqrt($squared / count($ratings));
}

function rankWeight(int $rank): float
{
    return 1 / log($rank + 1, 2);
}

function rankingMetrics(array $items, array $relevant, int $cutoff): object
{
    $hits = 0;
    $dcg = $averagePrecision = $reciprocalRank = 0.0;
    for ($index = 0; $index < $cutoff; $index++) {
        if (!isset($relevant[$items[$index]])) {
            continue;
        }
        $hits++;
        $dcg += rankWeight($index + 1);
        $averagePrecision += $hits / ($index + 1);
        if ($reciprocalRank == 0.0) {
            $reciprocalRank = 1 / ($index + 1);
        }
    }
    $idealCount = min($cutoff, count($relevant));
    $ideal = 0.0;
    for ($rank = 1; $rank <= $idealCount; $rank++) {
        $ideal += rankWeight($rank);
    }
    return (object) ['hits' => $hits, 'recall' => $hits / count($relevant), 'ndcg' => $dcg / $ideal,
        'ap' => $averagePrecision / $idealCount, 'rr' => $reciprocalRank];
}
