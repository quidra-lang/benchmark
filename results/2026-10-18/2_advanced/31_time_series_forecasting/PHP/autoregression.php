<?php

require_once __DIR__ . '/decomposition.php';

function difference(array $values, string $kind, int $season): object
{
    $offset = ['none' => 0, 'first' => 1, 'seasonal' => $season, 'both' => $season + 1][$kind];
    $result = [];
    for ($t = $offset; $t < count($values); $t++) {
        if ($kind === 'none') {
            $result[] = $values[$t];
        } elseif ($kind === 'first') {
            $result[] = $values[$t] - $values[$t - 1];
        } elseif ($kind === 'seasonal') {
            $result[] = $values[$t] - $values[$t - $season];
        } else {
            $result[] = ($values[$t] - $values[$t - 1]) - ($values[$t - $season] - $values[$t - $season - 1]);
        }
    }
    return (object) ['values' => $result, 'offset' => $offset];
}

function autocorrelation(array $values, int $maximumLag): object
{
    $average = mean($values);
    $differences = array_map(fn($value) => $value - $average, $values);
    $squares = 0.0;
    foreach ($differences as $value) {
        $squares += $value * $value;
    }
    $variance = $squares / count($values);
    $correlations = [1.0];
    for ($lag = 1; $lag <= $maximumLag; $lag++) {
        $total = 0.0;
        for ($i = 0; $i < count($values) - $lag; $i++) {
            $total += $differences[$i] * $differences[$i + $lag];
        }
        $correlations[] = $total / count($values) / $variance;
    }
    return (object) ['mean' => $average, 'variance' => $variance, 'correlations' => $correlations];
}

function durbinLevinson(array $correlations): object
{
    $rows = [[]];
    $variances = [1.0];
    $partial = [0.0];
    for ($k = 1; $k < count($correlations); $k++) {
        $previous = $rows[$k - 1];
        $total = 0.0;
        for ($j = 1; $j < $k; $j++) {
            $total += $previous[$j - 1] * $correlations[$k - $j];
        }
        $theta = ($correlations[$k] - $total) / $variances[$k - 1];
        $row = [];
        for ($j = 1; $j < $k; $j++) {
            $row[] = $previous[$j - 1] - $theta * $previous[$k - $j - 1];
        }
        $row[] = $theta;
        $rows[] = $row;
        $variances[] = $variances[$k - 1] * (1.0 - $theta * $theta);
        $partial[] = $theta;
    }
    return (object) compact('rows', 'variances', 'partial');
}

function arResiduals(array $values, float $average, array $coefficients): array
{
    $result = [];
    for ($i = count($coefficients); $i < count($values); $i++) {
        $total = 0.0;
        for ($j = 1; $j <= count($coefficients); $j++) {
            $total += $coefficients[$j - 1] * ($values[$i - $j] - $average);
        }
        $result[] = $values[$i] - $average - $total;
    }
    return $result;
}

function arForecast(object $model, int $origin, int $steps, int $season): array
{
    $differenced = array_slice($model->differenced, 0, $origin - $model->offset);
    $appended = [];
    for ($k = 0; $k < $steps; $k++) {
        $total = 0.0;
        for ($j = 1; $j <= count($model->coefficients); $j++) {
            $total += $model->coefficients[$j - 1] * ($differenced[count($differenced) - $j] - $model->average);
        }
        $value = $model->average + $total;
        $differenced[] = $value;
        $appended[] = $value;
    }
    $original = array_slice($model->values, 0, $origin);
    $result = [];
    foreach ($appended as $value) {
        $length = count($original);
        $next = $value;
        if ($model->difference === 'first') {
            $next = $value + $original[$length - 1];
        } elseif ($model->difference === 'seasonal') {
            $next = $value + $original[$length - $season];
        } elseif ($model->difference === 'both') {
            $next = $value + $original[$length - 1] + $original[$length - $season] - $original[$length - $season - 1];
        }
        $original[] = $next;
        $result[] = $next;
    }
    return $result;
}

function ljungBox(array $values, array $lags): array
{
    $correlations = autocorrelation($values, max($lags))->correlations;
    $result = [];
    foreach ($lags as $lag) {
        $total = 0.0;
        for ($k = 1; $k <= $lag; $k++) {
            $total += $correlations[$k] * $correlations[$k] / (count($values) - $k);
        }
        $q = count($values) * (count($values) + 2) * $total;
        $x = $q / 2.0;
        $term = $terms = 1.0;
        for ($i = 1; $i <= intdiv($lag, 2) - 1; $i++) {
            $term = $term * $x / $i;
            $terms += $term;
        }
        $result[] = (object) ['lag' => $lag, 'q' => $q, 'p' => exp(-$x) * $terms];
    }
    return $result;
}
