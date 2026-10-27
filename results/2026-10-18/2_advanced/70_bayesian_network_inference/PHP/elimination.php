<?php

function interactionGraph($initial)
{
    $graph = [];
    foreach ($initial as $factor) {
        foreach ($factor['variables'] as $variable) {
            if (!isset($graph[$variable])) {
                $graph[$variable] = [];
            }
        }
        for ($i = 0; $i < count($factor['variables']); $i++) {
            for ($j = $i + 1; $j < count($factor['variables']); $j++) {
                $first = $factor['variables'][$i];
                $second = $factor['variables'][$j];
                $graph[$first][$second] = true;
                $graph[$second][$first] = true;
            }
        }
    }
    return $graph;
}

function graphMetrics($graph, $variable)
{
    $neighbors = array_keys($graph[$variable]);
    sort($neighbors, SORT_NUMERIC);
    $fill = 0;
    for ($i = 0; $i < count($neighbors); $i++) {
        for ($j = $i + 1; $j < count($neighbors); $j++) {
            if (!isset($graph[$neighbors[$i]][$neighbors[$j]])) {
                $fill++;
            }
        }
    }
    return ['variable' => $variable, 'neighbors' => $neighbors, 'fill' => $fill, 'degree' => count($neighbors)];
}

function eliminationPlan($initial, $variables, $method, $given, $sizes)
{
    $graph = interactionGraph($initial);
    $pending = array_fill_keys($variables, true);
    $steps = [];
    $maximum = $total = 0;
    while ($pending) {
        $choice = null;
        if ($method === 'given') {
            foreach ($given as $variable) {
                if (isset($pending[$variable])) {
                    $choice = graphMetrics($graph, $variable);
                    break;
                }
            }
        } else {
            foreach ($pending as $variable => $unused) {
                $candidate = graphMetrics($graph, $variable);
                if ($choice === null || $candidate['fill'] < $choice['fill'] ||
                    ($candidate['fill'] === $choice['fill'] && ($candidate['degree'] < $choice['degree'] ||
                    ($candidate['degree'] === $choice['degree'] && $variable < $choice['variable'])))) {
                    $choice = $candidate;
                }
            }
        }
        $scope = array_merge([$choice['variable']], $choice['neighbors']);
        sort($scope, SORT_NUMERIC);
        $size = assignmentCount($scope, $sizes);
        $steps[] = ['variable' => $choice['variable'], 'fill' => $choice['fill'], 'variables' => $scope, 'size' => $size];
        $maximum = max($maximum, $size);
        $total += $size;
        foreach ($choice['neighbors'] as $i => $first) {
            for ($j = $i + 1; $j < count($choice['neighbors']); $j++) {
                $second = $choice['neighbors'][$j];
                $graph[$first][$second] = true;
                $graph[$second][$first] = true;
            }
            unset($graph[$first][$choice['variable']]);
        }
        unset($graph[$choice['variable']], $pending[$choice['variable']]);
    }
    return ['steps' => $steps, 'maximum' => $maximum, 'total' => $total];
}

function executePlan($initial, $plan, $sizes, $maximize = false)
{
    $sequence = $initial;
    $products = [];
    foreach ($plan['steps'] as $step) {
        $selected = $remaining = [];
        foreach ($sequence as $factor) {
            if (in_array($step['variable'], $factor['variables'], true)) {
                $selected[] = $factor;
            } else {
                $remaining[] = $factor;
            }
        }
        $product = factorProduct($selected, $sizes);
        if ($maximize) {
            $products[] = ['variable' => $step['variable'], 'factor' => $product];
        }
        $remaining[] = removeVariable($product, $step['variable'], $sizes, $maximize);
        $sequence = $remaining;
    }
    return ['factor' => factorProduct($sequence, $sizes), 'products' => $products];
}

function traceback($result, $evidence, $sizes)
{
    $assignment = array_fill(0, count($sizes), 0);
    foreach ($evidence as $variable => $state) {
        $assignment[$variable] = $state;
    }
    for ($index = count($result['products']) - 1; $index >= 0; $index--) {
        $variable = $result['products'][$index]['variable'];
        $factor = $result['products'][$index]['factor'];
        $best = 0;
        $assignment[$variable] = 0;
        $maximum = factorValue($factor, $assignment, $sizes);
        for ($state = 1; $state < $sizes[$variable]; $state++) {
            $assignment[$variable] = $state;
            $value = factorValue($factor, $assignment, $sizes);
            if ($value > $maximum) {
                $maximum = $value;
                $best = $state;
            }
        }
        $assignment[$variable] = $best;
    }
    return $assignment;
}
