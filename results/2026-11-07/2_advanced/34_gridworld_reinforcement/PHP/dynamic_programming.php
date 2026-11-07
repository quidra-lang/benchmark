<?php

function floorDivide(int $numerator, int $denominator): int
{
    $quotient = intdiv($numerator, $denominator);
    return $numerator < 0 && $numerator % $denominator !== 0 ? $quotient - 1 : $quotient;
}

function firstMaximum(array $values): int
{
    $best = 0;
    for ($action = 1; $action < count($values); $action++) {
        if ($values[$action] > $values[$best]) {
            $best = $action;
        }
    }
    return $best;
}

function bellman(TransitionModel $model, array $values, int $state, int $action, int $gamma): int
{
    $total = 0;
    foreach ($model->transitions[$state][$action] as $transition) {
        $future = $transition->next < 0 ? 0 : floorDivide($gamma * $values[$transition->next], 100);
        $total += $transition->weight * (10000 * $transition->reward + $future);
    }
    return floorDivide($total, $model->denominator);
}

function rowValues(TransitionModel $model, array $values, int $state, int $gamma): array
{
    $row = [];
    for ($action = 0; $action < 4; $action++) {
        $row[] = bellman($model, $values, $state, $action, $gamma);
    }
    return $row;
}

function actionValues(TransitionModel $model, array $values, int $gamma): array
{
    $table = [];
    foreach ($values as $state => $value) {
        $table[] = rowValues($model, $values, $state, $gamma);
    }
    return $table;
}

function greedyPolicy(array $table): array
{
    return array_map('firstMaximum', $table);
}

function valueIteration(TransitionModel $model, int $gamma, int $theta): object
{
    $values = array_fill(0, count($model->world->states), 0);
    $changes = [];
    while (true) {
        $next = [];
        $delta = 0;
        foreach (actionValues($model, $values, $gamma) as $state => $row) {
            $next[] = $row[firstMaximum($row)];
            $delta = max($delta, abs($next[$state] - $values[$state]));
        }
        $values = $next;
        $changes[] = $delta;
        if ($delta <= $theta) {
            return (object) ['values' => $values, 'changes' => $changes, 'iterations' => count($changes)];
        }
    }
}

function inPlaceValueIteration(TransitionModel $model, int $gamma, int $theta): object
{
    $values = array_fill(0, count($model->world->states), 0);
    $iterations = 0;
    while (true) {
        $delta = 0;
        foreach ($values as $state => $value) {
            $row = rowValues($model, $values, $state, $gamma);
            $next = $row[firstMaximum($row)];
            $delta = max($delta, abs($next - $values[$state]));
            $values[$state] = $next;
        }
        $iterations++;
        if ($delta <= $theta) {
            return (object) compact('values', 'iterations');
        }
    }
}

function evaluatePolicy(TransitionModel $model, array $policy, int $gamma, int $theta, ?array $initial = null): object
{
    $values = $initial ?? array_fill(0, count($policy), 0);
    $sweeps = 0;
    while (true) {
        $delta = 0;
        foreach ($policy as $state => $action) {
            $next = bellman($model, $values, $state, $action, $gamma);
            $delta = max($delta, abs($next - $values[$state]));
            $values[$state] = $next;
        }
        $sweeps++;
        if ($delta <= $theta) {
            return (object) compact('values', 'sweeps');
        }
    }
}

function policyIteration(TransitionModel $model, int $gamma, int $theta): object
{
    $policy = array_fill(0, count($model->world->states), 0);
    $values = array_fill(0, count($policy), 0);
    $rounds = [];
    while (true) {
        $evaluation = evaluatePolicy($model, $policy, $gamma, $theta, $values);
        $values = $evaluation->values;
        $next = greedyPolicy(actionValues($model, $values, $gamma));
        $changed = 0;
        foreach ($policy as $state => $action) {
            if ($next[$state] !== $action) {
                $changed++;
            }
        }
        $rounds[] = (object) ['number' => count($rounds) + 1, 'sweeps' => $evaluation->sweeps,
            'changed' => $changed, 'start' => $values[$model->world->startIndex]];
        $policy = $next;
        if ($changed === 0) {
            return (object) compact('values', 'policy', 'rounds');
        }
    }
}
