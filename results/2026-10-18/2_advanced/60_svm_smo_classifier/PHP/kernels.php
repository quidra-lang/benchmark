<?php

require_once __DIR__ . '/evaluation.php';

function kernel_value($kernel, $a, $b)
{
    if ($kernel['kind'] === 'linear') return $a[0] * $b[0] + $a[1] * $b[1];
    if ($kernel['kind'] === 'poly') {
        $s = $kernel['gamma'] * ($a[0] * $b[0] + $a[1] * $b[1]) + $kernel['coef0'];
        $result = 1.0;
        for ($i = 0; $i < $kernel['degree']; $i++) $result *= $s;
        return $result;
    }
    $e1 = $a[0] - $b[0];
    $e2 = $a[1] - $b[1];
    return exp(-$kernel['gamma'] * ($e1 * $e1 + $e2 * $e2));
}

function kernel_matrix($kernel, $points)
{
    $matrix = [];
    foreach ($points as $a) {
        $row = [];
        foreach ($points as $b) $row[] = kernel_value($kernel, $a, $b);
        $matrix[] = $row;
    }
    return $matrix;
}

function matrix_subset($matrix, $indices)
{
    $result = [];
    foreach ($indices as $i) {
        $row = [];
        foreach ($indices as $j) $row[] = $matrix[$i][$j];
        $result[] = $row;
    }
    return $result;
}

function kernel_description($kernel)
{
    if ($kernel['kind'] === 'linear') return 'linear';
    if ($kernel['kind'] === 'poly') return 'poly degree ' . $kernel['degree'] . ' gamma ' . fixed($kernel['gamma'], 4) . ' coef0 ' . fixed($kernel['coef0'], 4);
    return 'rbf gamma ' . fixed($kernel['gamma'], 4);
}
