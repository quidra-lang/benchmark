<?php

function evaluateCox($subjects, $vectors, $beta)
{
    $p = count($beta);
    $predictors = $risks = [];
    foreach ($subjects as $j => $subject) {
        $predictor = 0.0;
        for ($c = 0; $c < $p; $c++) {
            $predictor += $beta[$c] * $vectors[$j][$c];
        }
        $predictors[] = $predictor;
        $risks[] = exp($predictor);
    }
    $order = array_keys($subjects);
    usort($order, fn($a, $b) => ($subjects[$b]['time'] <=> $subjects[$a]['time']) ?:
        ($subjects[$a]['id'] <=> $subjects[$b]['id']));
    $s0 = 0.0;
    $s1 = array_fill(0, $p, 0.0);
    $s2 = array_fill(0, $p, array_fill(0, $p, 0.0));
    $loglik = 0.0;
    $score = array_fill(0, $p, 0.0);
    $information = array_fill(0, $p, array_fill(0, $p, 0.0));
    $eventRows = [];
    $position = 0;
    while ($position < count($order)) {
        $time = $subjects[$order[$position]]['time'];
        $deaths = [];
        while ($position < count($order) && $subjects[$order[$position]]['time'] === $time) {
            $j = $order[$position++];
            $s0 += $risks[$j];
            for ($c = 0; $c < $p; $c++) {
                $s1[$c] += $risks[$j] * $vectors[$j][$c];
                for ($d = 0; $d < $p; $d++) {
                    $s2[$c][$d] += $risks[$j] * $vectors[$j][$c] * $vectors[$j][$d];
                }
            }
            if ($subjects[$j]['event'] === 1) {
                $deaths[] = $j;
            }
        }
        $e = count($deaths);
        if ($e === 0) {
            continue;
        }
        $predictorSum = 0.0;
        $covariateSum = array_fill(0, $p, 0);
        foreach ($deaths as $j) {
            $predictorSum += $predictors[$j];
            for ($c = 0; $c < $p; $c++) {
                $covariateSum[$c] += $vectors[$j][$c];
            }
        }
        $loglik += $predictorSum - $e * log($s0);
        for ($c = 0; $c < $p; $c++) {
            $score[$c] += $covariateSum[$c] - $e * $s1[$c] / $s0;
            for ($d = 0; $d < $p; $d++) {
                $information[$c][$d] += $e * ($s2[$c][$d] / $s0 - ($s1[$c] / $s0) * ($s1[$d] / $s0));
            }
        }
        $eventRows[$time] = ['time' => $time, 'events' => $e, 's0' => $s0, 's1' => $s1];
    }
    return ['loglik' => $loglik, 'score' => $score, 'information' => $information,
        'predictors' => $predictors, 'risks' => $risks, 'eventRows' => $eventRows];
}

function fitCox($subjects, $vectors)
{
    $beta = array_fill(0, count($vectors[0]), 0.0);
    $iterations = [];
    $nullEvaluation = null;
    for ($s = 1; $s <= 25; $s++) {
        $current = evaluateCox($subjects, $vectors, $beta);
        if ($s === 1) {
            $nullEvaluation = $current;
        }
        $delta = solve($current['information'], $current['score']);
        for ($c = 0; $c < count($beta); $c++) {
            $beta[$c] += $delta[$c];
        }
        $iterations[] = ['iteration' => $s, 'loglik' => $current['loglik'], 'beta' => $beta];
    }
    return ['beta' => $beta, 'iterations' => $iterations, 'nullEvaluation' => $nullEvaluation,
        'finalEvaluation' => evaluateCox($subjects, $vectors, $beta)];
}
