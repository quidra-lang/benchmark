<?php

function standardize(array $values, array $means, array $scales): array
{
    $result = [];
    foreach ($values as $j => $value) $result[] = $value === null ? 0.0 : ($value - $means[$j]) / $scales[$j];
    return $result;
}

function prepareData(array $rows, string $scaling): array
{
    $dimension = count($rows[0]);
    $count = count($rows);
    $means = [];
    for ($j = 0; $j < $dimension; $j++) {
        $total = 0.0;
        foreach ($rows as $row) $total += $row[$j];
        $means[] = $total / $count;
    }
    $covariance = matZeros($dimension);
    for ($j = 0; $j < $dimension; $j++) {
        for ($k = $j; $k < $dimension; $k++) {
            $total = 0.0;
            foreach ($rows as $row) $total += ($row[$j] - $means[$j]) * ($row[$k] - $means[$k]);
            $covariance[$j][$k] = $covariance[$k][$j] = $total / ($count - 1);
        }
    }
    $deviations = [];
    for ($j = 0; $j < $dimension; $j++) $deviations[] = sqrt($covariance[$j][$j]);
    $correlation = matZeros($dimension);
    for ($j = 0; $j < $dimension; $j++) {
        for ($k = 0; $k < $dimension; $k++) {
            $correlation[$j][$k] = $j === $k ? 1.0 : $covariance[$j][$k] / ($deviations[$j] * $deviations[$k]);
        }
    }
    $scales = $scaling === 'covariance' ? array_fill(0, $dimension, 1.0) : $deviations;
    return ['means' => $means, 'covariance' => $covariance, 'deviations' => $deviations, 'correlation' => $correlation,
        'scales' => $scales, 'matrix' => $scaling === 'covariance' ? $covariance : $correlation,
        'standardized' => array_map(fn($row) => standardize($row, $means, $scales), $rows)];
}

function pcaScores(array $standardized, array $vectors): array
{
    return array_map(fn($vector) => vecDot($standardized, $vector), $vectors);
}

function pcaResiduals(array $standardized, array $scores, array $vectors, int $retained): array
{
    $residuals = [];
    foreach ($standardized as $feature => $value) {
        $fitted = 0.0;
        for ($k = 0; $k < $retained; $k++) $fitted += $scores[$k] * $vectors[$k][$feature];
        $residuals[] = $value - $fitted;
    }
    return $residuals;
}

function pcaTSquared(array $scores, array $values, int $retained): float
{
    $total = 0.0;
    for ($k = 0; $k < $retained; $k++) $total += ($scores[$k] * $scores[$k]) / $values[$k];
    return $total;
}
