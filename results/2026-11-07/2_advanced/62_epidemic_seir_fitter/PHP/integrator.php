<?php

function rk4(object $model, array $state, float $multiplier): array
{
    $step = 0.25;
    $half = $step / 2;
    $sixth = $step / 6;
    $rate = $model->rate;
    $k1 = $rate($state, $multiplier);
    $next = [];
    foreach ($state as $i => $value) {
        $next[] = $value + $half * $k1[$i];
    }
    $k2 = $rate($next, $multiplier);
    $next = [];
    foreach ($state as $i => $value) {
        $next[] = $value + $half * $k2[$i];
    }
    $k3 = $rate($next, $multiplier);
    $next = [];
    foreach ($state as $i => $value) {
        $next[] = $value + $step * $k3[$i];
    }
    $k4 = $rate($next, $multiplier);
    $result = [];
    foreach ($state as $i => $value) {
        $result[] = $value + $sixth * ((($k1[$i] + 2 * $k2[$i]) + 2 * $k3[$i]) + $k4[$i]);
    }
    return $result;
}

function simulate(object $model, array $multipliers, ?array $initial = null): array
{
    $state = $initial ?? $model->initial;
    $days = [];
    foreach ($multipliers as $multiplier) {
        foreach ($model->inflows as $index) {
            $state[$index] = 0.0;
        }
        for ($step = 0; $step < 4; $step++) {
            $state = rk4($model, $state, $multiplier);
        }
        $days[] = $state;
    }
    return $days;
}
