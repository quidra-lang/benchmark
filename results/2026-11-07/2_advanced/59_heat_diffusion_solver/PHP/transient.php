<?php

function flow(object $model, array $field, int $p, int $start, int $end): float
{
    $total = 0;
    $first = true;
    for ($direction = $start; $direction < $end; $direction++) {
        $face = $model->faces[$p][$direction];
        if ($face->q < 0 && $face->theta === null) continue;
        $outside = $face->q >= 0 ? $field[$face->q] : $face->theta;
        $term = $face->g * ($outside - $field[$p]);
        $total = $first ? $term : $total + $term;
        $first = false;
    }
    return $total;
}

function hx(object $model, array $field, int $p): float { return flow($model, $field, $p, 0, 2); }
function hy(object $model, array $field, int $p): float { return flow($model, $field, $p, 2, 4); }
function totalFlow(object $model, array $field, int $p): float { return flow($model, $field, $p, 0, 4); }

function thomas(array $lower, array $diagonal, array $upper, array $rhs): array
{
    $size = count($diagonal);
    $upperPrime = [$upper[0] / $diagonal[0]];
    $rhsPrime = [$rhs[0] / $diagonal[0]];
    for ($i = 1; $i < $size; $i++) {
        $divisor = $diagonal[$i] - $lower[$i] * $upperPrime[$i - 1];
        $upperPrime[] = $upper[$i] / $divisor;
        $rhsPrime[] = ($rhs[$i] - $lower[$i] * $rhsPrime[$i - 1]) / $divisor;
    }
    $answer = array_fill(0, $size, 0);
    $answer[$size - 1] = $rhsPrime[$size - 1];
    for ($i = $size - 2; $i >= 0; $i--) $answer[$i] = $rhsPrime[$i] - $upperPrime[$i] * $answer[$i + 1];
    return $answer;
}

function sweep(object $model, float $tau, array $rhs, bool $horizontal): array
{
    $lines = $horizontal ? $model->height : $model->width;
    $size = $horizontal ? $model->width : $model->height;
    $direction = $horizontal ? 0 : 2;
    $field = array_fill(0, $model->count, 0);
    for ($line = 0; $line < $lines; $line++) {
        $cells = $lower = $diagonal = $upper = $adjusted = [];
        for ($i = 0; $i < $size; $i++) {
            $p = $horizontal ? $line * $model->width + $i : $i * $model->width + $line;
            $cells[] = $p;
            $before = $model->faces[$p][$direction];
            $after = $model->faces[$p][$direction + 1];
            $lower[] = $before->q >= 0 ? -$before->g : 0;
            $diagonal[] = $model->capacities[$p] / $tau + $before->g + $after->g;
            $upper[] = $after->q >= 0 ? -$after->g : 0;
            $value = $rhs[$p];
            if ($before->theta !== null) $value += $before->g * $before->theta;
            if ($after->theta !== null) $value += $after->g * $after->theta;
            $adjusted[] = $value;
        }
        $answer = thomas($lower, $diagonal, $upper, $adjusted);
        for ($i = 0; $i < $size; $i++) $field[$cells[$i]] = $answer[$i];
    }
    return $field;
}

function ftcs(object $model, array $old, array $source, float $dt): object
{
    $field = [];
    for ($p = 0; $p < $model->count; $p++) $field[] = $old[$p] + $dt * (totalFlow($model, $old, $p) + $source[$p]) / $model->capacities[$p];
    return (object) ['field' => $field, 'intermediate' => null];
}

function backwardEuler(object $model, array $old, array $source, float $dt): object
{
    $oldVertical = $rhs = [];
    for ($p = 0; $p < $model->count; $p++) {
        $oldVertical[$p] = hy($model, $old, $p);
        $rhs[$p] = $model->capacities[$p] / $dt * $old[$p] + $oldVertical[$p] + $source[$p];
    }
    $intermediate = sweep($model, $dt, $rhs, true);
    for ($p = 0; $p < $model->count; $p++) $rhs[$p] = $model->capacities[$p] / $dt * $intermediate[$p] - $oldVertical[$p];
    return (object) ['field' => sweep($model, $dt, $rhs, false), 'intermediate' => $intermediate];
}

function crankNicolson(object $model, array $old, array $source, float $dt): object
{
    $tau = $dt / 2;
    $rhs = [];
    for ($p = 0; $p < $model->count; $p++) $rhs[$p] = $model->capacities[$p] / $tau * $old[$p] + hy($model, $old, $p) + $source[$p];
    $intermediate = sweep($model, $tau, $rhs, true);
    for ($p = 0; $p < $model->count; $p++) $rhs[$p] = $model->capacities[$p] / $tau * $intermediate[$p] + hx($model, $intermediate, $p) + $source[$p];
    return (object) ['field' => sweep($model, $tau, $rhs, false), 'intermediate' => $intermediate];
}
