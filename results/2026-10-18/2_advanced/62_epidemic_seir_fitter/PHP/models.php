<?php

function seird(object $data, float $beta, float $gamma, ?float $sigma = null): object
{
    $sigma = $sigma ?? $data->params->sigma;
    $N = $data->N;
    $fatality = $data->fatality;
    $p = $data->params;
    $rate = function ($state, $multiplier) use ($N, $fatality, $beta, $gamma, $sigma) {
        [$S, $E, $I] = $state;
        $flow = $beta * $multiplier * $S * $I / $N;
        return [-$flow, $flow - $sigma * $E, $sigma * $E - $gamma * $I,
            (1 - $fatality) * $gamma * $I, $fatality * $gamma * $I, $sigma * $E];
    };
    return (object) ['initial' => [$N - $p->exposed - $p->infectious, $p->exposed, $p->infectious, 0.0, 0.0, 0.0], 'inflows' => [5], 'rate' => $rate];
}

function sir(object $data, float $beta, float $gamma): object
{
    $N = $data->N;
    $p = $data->params;
    $rate = function ($state, $multiplier) use ($N, $beta, $gamma) {
        [$S, $I] = $state;
        $flow = $beta * $multiplier * $S * $I / $N;
        return [-$flow, $flow - $gamma * $I, $gamma * $I, $flow];
    };
    return (object) ['initial' => [$N - $p->exposed - $p->infectious, $p->exposed + $p->infectious, 0.0, 0.0], 'inflows' => [3], 'rate' => $rate];
}

function ageSeird(object $data, float $beta, float $gamma, array $matrix): object
{
    $groups = $data->groups;
    $N = $data->N;
    $p = $data->params;
    $initial = [];
    $inflows = [];
    foreach ($groups as $g => $group) {
        $exposed = $p->exposed * $group->population / $N;
        $infectious = $p->infectious * $group->population / $N;
        array_push($initial, $group->population - $exposed - $infectious, $exposed, $infectious, 0.0, 0.0, 0.0);
        $inflows[] = 6 * $g + 5;
    }
    $rate = function ($state, $multiplier) use ($groups, $p, $matrix, $beta, $gamma) {
        $rates = [];
        foreach ($groups as $g => $group) {
            $contacts = 0.0;
            foreach ($groups as $h => $other) {
                $contacts += $matrix[$g][$h] * $state[6 * $h + 2] / $other->population;
            }
            $lambda = $beta * $multiplier * $contacts;
            $flow = $lambda * $state[6 * $g];
            $E = $state[6 * $g + 1];
            $I = $state[6 * $g + 2];
            array_push($rates, -$flow, $flow - $p->sigma * $E, $p->sigma * $E - $gamma * $I,
                (1 - $group->fatality) * $gamma * $I, $group->fatality * $gamma * $I, $p->sigma * $E);
        }
        return $rates;
    };
    return (object) compact('initial', 'inflows', 'rate');
}

function generationModel(float $sigma, float $gamma): object
{
    $rate = function ($state, $multiplier) use ($sigma, $gamma) {
        [$E, $I] = $state;
        return [-$sigma * $E, $sigma * $E - $gamma * $I, $gamma * $I];
    };
    return (object) ['initial' => [1.0, 0.0, 0.0], 'inflows' => [2], 'rate' => $rate];
}
