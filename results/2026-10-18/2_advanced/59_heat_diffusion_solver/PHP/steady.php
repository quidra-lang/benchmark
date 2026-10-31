<?php

function numerator(object $model, array $field, array $source, int $p): float
{
    $value = 0;
    $first = true;
    foreach ($model->faces[$p] as $face) {
        if ($face->q < 0 && $face->theta === null) continue;
        $term = $face->g * ($face->q >= 0 ? $field[$face->q] : $face->theta);
        $value = $first ? $term : $value + $term;
        $first = false;
    }
    return $value + $source[$p];
}

function iterateSteady(object $model, array $source, string $method, float $initial, float $tolerance, int $maximum, float $omega = 1): object
{
    $field = array_fill(0, $model->count, $initial);
    $deltas = [];
    $converged = false;
    for ($iteration = 1; $iteration <= $maximum; $iteration++) {
        $previous = $field;
        for ($p = 0; $p < $model->count; $p++) {
            $y = numerator($model, $method === 'jacobi' ? $previous : $field, $source, $p) / $model->diagonal[$p];
            $field[$p] = $method === 'jacobi' || $method === 'gauss_seidel' ? $y : $field[$p] + $omega * ($y - $field[$p]);
        }
        $delta = 0;
        for ($p = 0; $p < $model->count; $p++) $delta = max($delta, abs($field[$p] - $previous[$p]));
        $deltas[] = $delta;
        if ($delta < $tolerance) {
            $converged = true;
            break;
        }
    }
    return (object) compact('field', 'deltas', 'converged');
}

function bandSolve(object $model, array $rightSides): array
{
    $n = $model->count;
    $width = $model->width;
    $matrix = array_fill(0, $n, array_fill(0, 2 * $width + 1, 0));
    for ($p = 0; $p < $n; $p++) {
        $matrix[$p][$width] = $model->diagonal[$p];
        foreach ($model->faces[$p] as $face) if ($face->q >= 0) $matrix[$p][$face->q - $p + $width] = -$face->g;
    }
    $vectors = $rightSides;
    for ($k = 0; $k < $n; $k++) {
        $end = min($n - 1, $k + $width);
        for ($i = $k + 1; $i <= $end; $i++) {
            $factor = $matrix[$i][$k - $i + $width] / $matrix[$k][$width];
            $matrix[$i][$k - $i + $width] = 0;
            for ($j = $k + 1; $j <= $end; $j++) $matrix[$i][$j - $i + $width] -= $factor * $matrix[$k][$j - $k + $width];
            foreach ($vectors as &$vector) $vector[$i] -= $factor * $vector[$k];
            unset($vector);
        }
    }
    $answers = [];
    foreach ($vectors as $vector) {
        $field = array_fill(0, $n, 0);
        for ($i = $n - 1; $i >= 0; $i--) {
            $value = $vector[$i];
            for ($j = $i + 1; $j <= min($n - 1, $i + $width); $j++) $value -= $matrix[$i][$j - $i + $width] * $field[$j];
            $field[$i] = $value / $matrix[$i][$width];
        }
        $answers[] = $field;
    }
    return $answers;
}

function maxResidual(object $model, array $rhs, array $field): float
{
    $maximum = 0;
    for ($p = 0; $p < $model->count; $p++) {
        $value = $rhs[$p];
        foreach ($model->faces[$p] as $face) if ($face->q >= 0) $value += $face->g * $field[$face->q];
        $value -= $model->diagonal[$p] * $field[$p];
        $maximum = max($maximum, abs($value));
    }
    return $maximum;
}
