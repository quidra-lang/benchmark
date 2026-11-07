<?php

require_once __DIR__ . '/stumps.php';
require_once __DIR__ . '/adaboost.php';

function exponential_update($rows, &$weights, $stump)
{
    foreach ($rows as $i => $row) $weights[$i] *= exp(-$row['label'] * $stump->output($row['values']));
    normalize($weights);
}

function real_boost($rows, $params)
{
    $plans = real_plans($rows, $params['bins']);
    $weights = array_fill(0, count($rows), 1 / count($rows));
    $rounds = [];
    $bound = 1.0;
    $stop = 'completed';
    for ($t = 0; $t < $params['rounds']; $t++) {
        $candidate = real_search($rows, $weights, $plans, $params['bins']);
        $z = $candidate['error'];
        if ($z >= 1 - $params['convergence']) { $stop = 'converged'; break; }
        $values = [];
        foreach ($candidate['positive'] as $b => $positive) $values[] = 0.5 * log(($positive + $params['smoothing']) / ($candidate['negative'][$b] + $params['smoothing']));
        $stump = new Stump($candidate['feature'], $candidate['cuts'], $values);
        $bound *= $z;
        $rounds[] = ['stump' => $stump, 'z' => $z, 'bound' => $bound, 'weights' => $weights];
        exponential_update($rows, $weights, $stump);
    }
    $cuts = array_column($plans, 'cuts');
    return compact('rounds', 'stop', 'cuts');
}

function gentle($rows, $params)
{
    $plans = prepare($rows);
    $targets = array_column($rows, 'label');
    $weights = array_fill(0, count($rows), 1 / count($rows));
    $rounds = [];
    for ($t = 0; $t < $params['rounds']; $t++) {
        $candidate = regression_search($rows, $targets, $weights, $plans);
        $stump = $candidate['stump'];
        $rounds[] = ['stump' => $stump, 'error' => $candidate['error'], 'weights' => $weights];
        exponential_update($rows, $weights, $stump);
    }
    return ['rounds' => $rounds, 'stop' => 'completed'];
}

function logit($rows, $params)
{
    $plans = prepare($rows);
    $scores = array_fill(0, count($rows), 0.0);
    $probabilities = array_fill(0, count($rows), 0.5);
    $rounds = [];
    for ($t = 0; $t < $params['rounds']; $t++) {
        $responses = [];
        $weights = [];
        foreach ($rows as $i => $row) {
            $probability = $probabilities[$i];
            $q = $probability * (1 - $probability);
            $response = (($row['label'] === 1 ? 1 : 0) - $probability) / $q;
            if ($response > $params['clip']) $response = $params['clip'];
            if ($response < -$params['clip']) $response = -$params['clip'];
            $responses[] = $response;
            $weights[] = $q;
        }
        normalize($weights);
        $selected = regression_search($rows, $responses, $weights, $plans);
        $values = [];
        foreach ($selected['stump']->values as $value) $values[] = $value / 2;
        $stump = new Stump($selected['stump']->feature, $selected['stump']->thresholds, $values);
        foreach ($rows as $i => $row) {
            $scores[$i] += $stump->output($row['values']);
            $probabilities[$i] = 1 / (1 + exp(-2 * $scores[$i]));
        }
        $loss = 0.0;
        foreach ($rows as $i => $row) $loss += log(1 + exp(-2 * $row['label'] * $scores[$i]));
        $loss /= count($rows);
        $rounds[] = ['stump' => $stump, 'error' => $selected['error'], 'loss' => $loss, 'weights' => $weights];
    }
    return ['rounds' => $rounds, 'stop' => 'completed'];
}
