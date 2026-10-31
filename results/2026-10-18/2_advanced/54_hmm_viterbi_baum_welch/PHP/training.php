<?php

require_once __DIR__ . '/model_io.php';
require_once __DIR__ . '/inference.php';

function empty_counts($model)
{
    $count = count($model['states']);
    return ['initial' => array_fill(0, $count, 0.0), 'transition' => array_fill(0, $count, array_fill(0, $count, 0.0)),
        'emission' => array_fill(0, $count, array_fill(0, count($model['symbols']), 0.0))];
}

function smoothed($model, $counts, $alpha, $name)
{
    $row = fn($values) => normalize_values(array_map(fn($value) => $value + $alpha, $values));
    return model_with_probabilities($model, $name, $row($counts['initial']), array_map($row, $counts['transition']), array_map($row, $counts['emission']));
}

function reestimate($model, $sequences, $pseudocount)
{
    $counts = empty_counts($model);
    $size = count($model['states']);
    foreach ($sequences as $observations) {
        $result = forward_backward($model, $observations);
        for ($i = 0; $i < $size; $i++) $counts['initial'][$i] += $result['gamma'][0][$i];
        foreach ($observations as $t => $observation) {
            for ($i = 0; $i < $size; $i++) {
                if ($observation >= 0) $counts['emission'][$i][$observation] += $result['gamma'][$t][$i];
                if ($t + 1 < count($observations)) for ($j = 0; $j < $size; $j++) {
                    $counts['transition'][$i][$j] += $result['factors'][$t][$i] * $model['transition'][$i][$j]
                        * emission_factor($model, $observations[$t + 1], $j) * $result['backward'][$t + 1][$j] / $result['scales'][$t + 1];
                }
            }
        }
    }
    return smoothed($model, $counts, $pseudocount, 'BAUM_WELCH');
}

function estimate_by_counting($model, $pairs, $alpha, $name)
{
    $counts = empty_counts($model);
    foreach ($pairs as $pair) {
        $observations = $pair['observations'];
        $path = $pair['path'];
        $counts['initial'][$path[0]]++;
        foreach ($observations as $t => $observation) {
            if ($observation >= 0) $counts['emission'][$path[$t]][$observation]++;
            if ($t + 1 < count($observations)) $counts['transition'][$path[$t]][$path[$t + 1]]++;
        }
    }
    return smoothed($model, $counts, $alpha, $name);
}

function total_loglik($model, $sequences)
{
    $total = 0.0;
    foreach ($sequences as $observations) $total += forward($model, $observations)['loglik'];
    return $total;
}
