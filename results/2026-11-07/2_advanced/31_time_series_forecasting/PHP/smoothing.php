<?php

require_once __DIR__ . '/decomposition.php';

function smooth(string $name, array $values, int $season, array $parameters): object
{
    $alpha = $parameters['alpha'];
    $beta = $parameters['beta'] ?? 0.0;
    $gamma = $parameters['gamma'] ?? 0.0;
    $phi = $parameters['phi'] ?? 1.0;
    $winters = $name === 'hw_add' || $name === 'hw_mult';
    $level = $winters ? mean(array_slice($values, 0, $season)) : $values[0];
    $slope = $name === 'ses' ? 0.0 : ($winters ? (mean(array_slice($values, $season, $season)) - $level) / $season :
        ($values[$season] - $values[0]) / $season);
    $seasonal = [];
    if ($winters) {
        foreach (array_slice($values, 0, $season) as $value) {
            $seasonal[] = $name === 'hw_add' ? $value - $level : $value / $level;
        }
    }
    $states = [(object) compact('level', 'slope', 'seasonal')];
    $residuals = [];
    foreach ($values as $t => $value) {
        $nextSlope = $slope;
        if ($name === 'ses') {
            $residuals[] = $value - $level;
            $nextLevel = $alpha * $value + (1.0 - $alpha) * $level;
        } elseif (!$winters) {
            $forecast = $level + $phi * $slope;
            $residuals[] = $value - $forecast;
            $nextLevel = $alpha * $value + (1.0 - $alpha) * $forecast;
            $nextSlope = $beta * ($nextLevel - $level) + (1.0 - $beta) * $phi * $slope;
        } else {
            $j = $t % $season;
            $u = $level + $slope;
            $q = $seasonal[$j];
            if ($name === 'hw_add') {
                $residuals[] = $value - ($u + $q);
                $nextLevel = $alpha * ($value - $q) + (1.0 - $alpha) * $u;
                $seasonal[$j] = $gamma * ($value - $u) + (1.0 - $gamma) * $q;
            } else {
                $residuals[] = $value - $u * $q;
                $nextLevel = $alpha * ($value / $q) + (1.0 - $alpha) * $u;
                $seasonal[$j] = $gamma * ($value / $u) + (1.0 - $gamma) * $q;
            }
            $nextSlope = $beta * ($nextLevel - $level) + (1.0 - $beta) * $slope;
        }
        $level = $nextLevel;
        $slope = $nextSlope;
        $states[] = (object) compact('level', 'slope', 'seasonal');
    }
    return (object) compact('states', 'residuals');
}

function smoothingForecast(string $name, object $state, int $origin, int $steps, int $season, array $parameters): array
{
    $values = [];
    $phi = $parameters['phi'] ?? 1.0;
    $power = $cumulative = $phi;
    for ($k = 1; $k <= $steps; $k++) {
        if ($name === 'ses') {
            $values[] = $state->level;
        } elseif ($name === 'holt' || $name === 'damped') {
            if ($k > 1) {
                $power *= $phi;
                $cumulative += $power;
            }
            $values[] = $state->level + $cumulative * $state->slope;
        } else {
            $seasonal = $state->seasonal[($origin + $k - 1) % $season];
            $values[] = $name === 'hw_add' ? $state->level + $k * $state->slope + $seasonal :
                ($state->level + $k * $state->slope) * $seasonal;
        }
    }
    return $values;
}
