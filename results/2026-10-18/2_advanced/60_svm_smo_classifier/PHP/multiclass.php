<?php

require_once __DIR__ . '/smo.php';

const PAIRS = [[1, 2], [1, 3], [2, 3]];

function multiclass_train($rows, $kernel, $C, $params)
{
    $points = array_column($rows, 'point');
    $Q = kernel_matrix($kernel, $points);
    $ovr = [];
    foreach ([1, 2, 3] as $k) {
        $labels = [];
        foreach ($rows as $row) $labels[] = $row['class'] === $k ? 1 : -1;
        $ovr[] = smo_train($points, $labels, $Q, $C, $kernel, $params);
    }
    $ovo = [];
    foreach (PAIRS as [$a, $b]) {
        $indices = []; $subsetPoints = []; $labels = [];
        foreach ($rows as $i => $row) if ($row['class'] === $a || $row['class'] === $b) {
            $indices[] = $i;
            $subsetPoints[] = $row['point'];
            $labels[] = $row['class'] === $a ? 1 : -1;
        }
        $ovo[] = smo_train($subsetPoints, $labels, matrix_subset($Q, $indices), $C, $kernel, $params);
    }
    return compact('ovr', 'ovo');
}

function multiclass_classify($models, $point)
{
    $g = []; $h = [];
    foreach ($models['ovr'] as $model) $g[] = decision($model, $point);
    foreach ($models['ovo'] as $model) $h[] = decision($model, $point);
    $ovr = 0;
    for ($k = 1; $k < 3; $k++) if ($g[$k] > $g[$ovr]) $ovr = $k;
    $votes = [0, 0, 0]; $scores = [0.0, 0.0, 0.0];
    foreach (PAIRS as $i => [$a, $b]) {
        $votes[($h[$i] > 0 ? $a : $b) - 1]++;
        $scores[$a - 1] += $h[$i]; $scores[$b - 1] -= $h[$i];
    }
    $maximum = max($votes);
    $ovo = -1; $tied = 0;
    for ($k = 0; $k < 3; $k++) if ($votes[$k] === $maximum) {
        $tied++;
        if ($ovo < 0 || $scores[$k] > $scores[$ovo]) $ovo = $k;
    }
    return ['g' => $g, 'h' => $h, 'votes' => $votes, 'scores' => $scores, 'ovr' => $ovr + 1, 'ovo' => $ovo + 1, 'voteTie' => $tied > 1];
}
