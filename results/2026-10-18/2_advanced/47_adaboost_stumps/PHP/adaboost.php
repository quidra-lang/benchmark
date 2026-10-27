<?php

require_once __DIR__ . '/stumps.php';

function normalize(&$weights)
{
    $total = 0.0;
    foreach ($weights as $weight) $total += $weight;
    foreach ($weights as &$weight) $weight /= $total;
    unset($weight);
    return $total;
}

function discrete($rows, $maximumRounds, $shrinkage = 1, $initialWeights = null)
{
    $plans = prepare($rows);
    $weights = $initialWeights ?? array_fill(0, count($rows), 1 / count($rows));
    $rounds = [];
    $bound = 1.0;
    $stop = 'completed';
    for ($t = 0; $t < $maximumRounds; $t++) {
        $candidate = discrete_search($rows, $weights, $plans);
        $error = $candidate['error'];
        if ($error >= 0.5) { $stop = 'weak'; break; }
        $alpha = $error <= 1e-10 ? 1 : $shrinkage * (0.5 * log((1 - $error) / $error));
        $polarity = $candidate['polarity'];
        $stump = new Stump($candidate['feature'], [$candidate['threshold']], [-$polarity * $alpha, $polarity * $alpha]);
        $before = $weights;
        foreach ($rows as $i => $row) {
            $decision = $row['values'][$candidate['feature']] > $candidate['threshold'] ? $polarity : -$polarity;
            $weights[$i] *= $decision === $row['label'] ? exp(-$alpha) : exp($alpha);
        }
        $z = normalize($weights);
        $bound *= $z;
        $rounds[] = ['stump' => $stump, 'polarity' => $polarity, 'error' => $error, 'alpha' => $alpha, 'z' => $z, 'bound' => $bound, 'weights' => $before];
        if ($error <= 1e-10) { $stop = 'perfect'; break; }
    }
    return compact('rounds', 'stop');
}

function samme($rows, $classes, $maximumRounds)
{
    $plans = prepare($rows);
    $weights = array_fill(0, count($rows), 1 / count($rows));
    $rounds = [];
    $stop = 'completed';
    for ($t = 0; $t < $maximumRounds; $t++) {
        $candidate = multiclass_search($rows, $weights, $plans, $classes);
        $stump = $candidate['stump'];
        $error = $candidate['error'];
        if ($error >= ($classes - 1) / $classes) { $stop = 'weak'; break; }
        $alpha = $error <= 1e-10 ? 1 : log((1 - $error) / $error) + log($classes - 1);
        foreach ($rows as $i => $row) if ($stump->output($row['values']) !== $row['category']) $weights[$i] *= exp($alpha);
        normalize($weights);
        $rounds[] = compact('stump', 'error', 'alpha');
        if ($error <= 1e-10) { $stop = 'perfect'; break; }
    }
    return compact('rounds', 'stop');
}
