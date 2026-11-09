<?php

function immInitialize($measurement, $params)
{
    return ['models' => [kalmanInitialize('CV', $measurement, $params), kalmanInitialize('CV', $measurement, $params)],
        'probabilities' => $params['IMM_INITIAL']];
}

function immAdvance($previous, $t, $measurement, $params)
{
    $transition = [array_slice($params['IMM_TRANSITION'], 0, 2), array_slice($params['IMM_TRANSITION'], 2, 2)];
    [$first, $second] = $previous['models'];
    [$mu1, $mu2] = $previous['probabilities'];
    $predicted = $models = $likelihoods = [];
    for ($j = 0; $j < 2; $j++) {
        $c = $transition[0][$j] * $mu1 + $transition[1][$j] * $mu2;
        $predicted[] = $c;
        $w1 = $transition[0][$j] * $mu1 / $c;
        $w2 = $transition[1][$j] * $mu2 / $c;
        $x = [];
        foreach ($first['x'] as $r => $value) {
            $x[] = $w1 * $value + $w2 * $second['x'][$r];
        }
        $p = matZeros(count($x));
        foreach ($first['P'] as $r => $row) {
            foreach ($row as $s => $value) {
                $p[$r][$s] = $w1 * ($value + ($first['x'][$r] - $x[$r]) * ($first['x'][$s] - $x[$s])) +
                    $w2 * ($second['P'][$r][$s] + ($second['x'][$r] - $x[$r]) * ($second['x'][$s] - $x[$s]));
            }
        }
        $prediction = kalmanPredict(['x' => $x, 'P' => $p], 'CV', $t, $params['IMM_Q'][$j]);
        if ($measurement === null) {
            $models[] = $prediction;
            $likelihoods[] = 1.0;
        } else {
            $residual = kalmanInnovation($prediction, $measurement, $params['SIGMA']);
            $models[] = kalmanUpdate($prediction, $residual);
            $likelihoods[] = exp(-$residual['d2'] / 2) / (2 * M_PI * sqrt(determinant2($residual['S'])));
        }
    }
    $denominator = $likelihoods[0] * $predicted[0] + $likelihoods[1] * $predicted[1];
    $probabilities = [$likelihoods[0] * $predicted[0] / $denominator, $likelihoods[1] * $predicted[1] / $denominator];
    return ['models' => $models, 'probabilities' => $probabilities];
}

function immEstimate($state)
{
    $result = [];
    foreach ($state['models'][0]['x'] as $r => $value) {
        $result[] = $state['probabilities'][0] * $value + $state['probabilities'][1] * $state['models'][1]['x'][$r];
    }
    return $result;
}
