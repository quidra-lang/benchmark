<?php

function goldenSearch(callable $objective, float $lower, float $upper, int $iterations): object
{
    $phi = 0.6180339887498949;
    $a = $lower;
    $b = $upper;
    $c = $b - $phi * ($b - $a);
    $d = $a + $phi * ($b - $a);
    $fc = $objective($c);
    $fd = $objective($d);
    $records = [(object) compact('a', 'b', 'c', 'd', 'fc', 'fd')];
    for ($i = 0; $i < $iterations; $i++) {
        if ($fc < $fd) {
            $b = $d;
            $d = $c;
            $fd = $fc;
            $c = $b - $phi * ($b - $a);
            $fc = $objective($c);
        } else {
            $a = $c;
            $c = $d;
            $fc = $fd;
            $d = $a + $phi * ($b - $a);
            $fd = $objective($d);
        }
        $records[] = (object) compact('a', 'b', 'c', 'd', 'fc', 'fd');
    }
    return $fc < $fd ? (object) ['point' => $c, 'value' => $fc, 'records' => $records]
        : (object) ['point' => $d, 'value' => $fd, 'records' => $records];
}

function vertexOrder(object $left, object $right): int
{
    return ($left->value <=> $right->value) ?: ($left->number <=> $right->number);
}

function nelderMead(callable $objective, float $beta, float $gamma, object $settings): object
{
    $nextNumber = 0;
    $evaluate = fn($point) => (object) ['point' => $point, 'value' => $objective($point[0], $point[1])];
    $number = function ($candidate) use (&$nextNumber) {
        $candidate->number = $nextNumber++;
        return $candidate;
    };
    $move = fn($origin, $target, $factor) => [$origin[0] + $factor * ($target[0] - $origin[0]), $origin[1] + $factor * ($target[1] - $origin[1])];
    $initial = [];
    foreach ([[$beta, $gamma], [$beta + $settings->deltaBeta, $gamma], [$beta, $gamma + $settings->deltaGamma]] as $point) {
        $initial[] = $number($evaluate($point));
    }
    $vertices = $initial;
    $records = [];
    for ($iteration = 1; $iteration <= $settings->iterations; $iteration++) {
        usort($vertices, 'vertexOrder');
        [$first, $second, $third] = $vertices;
        $center = [($first->point[0] + $second->point[0]) / 2, ($first->point[1] + $second->point[1]) / 2];
        $reflected = $evaluate([$center[0] + $settings->alpha * ($center[0] - $third->point[0]),
            $center[1] + $settings->alpha * ($center[1] - $third->point[1])]);
        $accepted = null;
        $operation = 'shrink';
        if ($reflected->value < $first->value) {
            $expanded = $evaluate($move($center, $reflected->point, $settings->chi));
            $accepted = $expanded->value < $reflected->value ? $expanded : $reflected;
            $operation = $expanded->value < $reflected->value ? 'expand' : 'reflect';
        } elseif ($reflected->value < $second->value) {
            $accepted = $reflected;
            $operation = 'reflect';
        } elseif ($reflected->value < $third->value) {
            $contracted = $evaluate($move($center, $reflected->point, $settings->psi));
            if ($contracted->value <= $reflected->value) {
                $accepted = $contracted;
                $operation = 'contract_out';
            }
        } else {
            $contracted = $evaluate($move($center, $third->point, $settings->psi));
            if ($contracted->value < $third->value) {
                $accepted = $contracted;
                $operation = 'contract_in';
            }
        }
        if ($accepted !== null) {
            $vertices = [$first, $second, $number($accepted)];
        } else {
            $smallerSecond = $number($evaluate($move($first->point, $second->point, $settings->omega)));
            $smallerThird = $number($evaluate($move($first->point, $third->point, $settings->omega)));
            $vertices = [$first, $smallerSecond, $smallerThird];
        }
        usort($vertices, 'vertexOrder');
        $records[] = (object) ['iteration' => $iteration, 'operation' => $operation, 'best' => $vertices[0]];
    }
    return (object) compact('initial', 'records', 'vertices');
}
