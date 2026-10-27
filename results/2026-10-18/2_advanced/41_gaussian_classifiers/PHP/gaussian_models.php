<?php

require_once __DIR__ . '/linalg.php';

function gm_statistics($rows, $features, $classCount, $prior)
{
    $dimension = count($features);
    $groups = array_fill(0, $classCount, []);
    foreach ($rows as $row) {
        $vector = [];
        foreach ($features as $feature) $vector[] = $row['values'][$feature];
        $groups[$row['class']][] = $vector;
    }
    $classes = [];
    foreach ($groups as $group) {
        $mean = [];
        for ($j = 0; $j < $dimension; $j++) {
            $total = 0.0;
            foreach ($group as $vector) $total += $vector[$j];
            $mean[] = $total / count($group);
        }
        $scatter = la_matrix($dimension);
        for ($a = 0; $a < $dimension; $a++) {
            for ($b = 0; $b < $dimension; $b++) {
                $total = 0.0;
                foreach ($group as $vector) $total += ($vector[$a] - $mean[$a]) * ($vector[$b] - $mean[$b]);
                $scatter[$a][$b] = $total;
            }
        }
        $count = count($group);
        $classes[] = ['count' => $count, 'mean' => $mean, 'scatter' => $scatter,
            'prior' => $prior === 'empirical' ? $count / count($rows) : 1 / $classCount];
    }
    $center = [];
    $variance = [];
    foreach ($features as $feature) {
        $total = 0.0;
        foreach ($rows as $row) $total += $row['values'][$feature];
        $mean = $total / count($rows);
        $center[] = $mean;
        $total = 0.0;
        foreach ($rows as $row) $total += ($row['values'][$feature] - $mean) * ($row['values'][$feature] - $mean);
        $variance[] = $total / count($rows);
    }
    return ['classes' => $classes, 'center' => $center, 'variance' => $variance, 'count' => count($rows)];
}

function gm_train($rows, $features, $type, $settings, $classCount)
{
    $data = gm_statistics($rows, $features, $classCount, $settings['prior']);
    $dimension = count($features);
    $maximumVariance = max($data['variance']);
    $added = $settings['epsilon'] * $maximumVariance;
    $pooled = null;
    if ($type === 'LDA') {
        $pooled = la_matrix($dimension);
        for ($a = 0; $a < $dimension; $a++) {
            for ($b = 0; $b < $dimension; $b++) {
                $total = 0.0;
                foreach ($data['classes'] as $group) $total += $group['scatter'][$a][$b];
                $pooled[$a][$b] = $total / (count($rows) - $classCount);
            }
        }
    }
    $classes = [];
    foreach ($data['classes'] as $group) {
        $covariance = $type === 'LDA' ? $pooled : la_matrix($dimension);
        if ($type === 'NB') {
            for ($j = 0; $j < $dimension; $j++) $covariance[$j][$j] = $group['scatter'][$j][$j] / $group['count'] + $added;
        } elseif ($type === 'QDA') {
            for ($a = 0; $a < $dimension; $a++) {
                for ($b = 0; $b < $dimension; $b++) {
                    $covariance[$a][$b] = $group['scatter'][$a][$b] / ($group['count'] - 1);
                    if ($a !== $b) $covariance[$a][$b] *= 1 - $settings['gamma'];
                }
            }
        }
        $lower = la_cholesky($covariance);
        $group['covariance'] = $covariance;
        $group['lower'] = $lower;
        $group['logDeterminant'] = la_log_determinant($lower);
        $classes[] = $group;
    }
    return compact('type', 'features', 'data', 'classes', 'maximumVariance', 'added');
}

function gm_predict($model, $vector, $costs = null)
{
    $halfConstant = count($model['features']) * log(2 * M_PI) / 2;
    $distances = [];
    $scores = [];
    foreach ($model['classes'] as $group) {
        $difference = [];
        foreach ($vector as $j => $value) $difference[] = $value - $group['mean'][$j];
        $distance = la_quadratic($group['lower'], $difference);
        $distances[] = $distance;
        $scores[] = log($group['prior']) - $halfConstant - $group['logDeterminant'] / 2 - $distance / 2;
    }
    $predicted = 0;
    for ($k = 1; $k < count($scores); $k++) if ($scores[$k] > $scores[$predicted]) $predicted = $k;
    $maximum = $scores[$predicted];
    $exponentials = [];
    $total = 0.0;
    foreach ($scores as $score) {
        $exponentials[] = exp($score - $maximum);
        $total += $exponentials[count($exponentials) - 1];
    }
    $posterior = [];
    $logPosterior = [];
    foreach ($scores as $k => $score) {
        $posterior[] = $exponentials[$k] / $total;
        $logPosterior[] = ($score - $maximum) - log($total);
    }
    $confidence = max($posterior);
    $decision = $predicted;
    if ($costs !== null) {
        $least = null;
        for ($b = 0; $b < count($scores); $b++) {
            $risk = 0.0;
            for ($k = 0; $k < count($scores); $k++) $risk += $posterior[$k] * $costs[$k][$b];
            if ($least === null || $risk < $least) {
                $least = $risk;
                $decision = $b;
            }
        }
    }
    return compact('predicted', 'posterior', 'logPosterior', 'confidence', 'decision', 'distances');
}

function gm_predict_row($model, $row, $costs = null)
{
    $vector = [];
    foreach ($model['features'] as $feature) $vector[] = $row['values'][$feature];
    return gm_predict($model, $vector, $costs);
}
