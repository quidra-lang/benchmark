<?php

function decode(object $instance, array $chromosome): object
{
    $next = array_fill(0, count($instance->jobs), 0);
    $ready = $next;
    $free = array_fill(0, $instance->machineCount, 0);
    $starts = $ends = array_fill(0, count($instance->operations), 0);
    $order = array_fill(0, $instance->machineCount, []);
    $makespan = 0;
    foreach ($chromosome as $number) {
        $job = $instance->byNumber[$number];
        $operation = $instance->operations[$job->operations[$next[$job->index]++]];
        $start = max($ready[$job->index], $free[$operation->machine]);
        $end = $start + $operation->duration;
        $starts[$operation->index] = $start;
        $ends[$operation->index] = $end;
        $order[$operation->machine][] = $operation->index;
        $ready[$job->index] = $end;
        $free[$operation->machine] = $end;
        $makespan = max($makespan, $end);
    }
    return (object) compact('starts', 'ends', 'order', 'makespan');
}

function tournament(array $evaluations, int $size, Minstd $rng): int
{
    $best = null;
    for ($i = 0; $i < $size; $i++) {
        $candidate = $rng->below(count($evaluations));
        if ($best === null || $evaluations[$candidate] < $evaluations[$best] ||
            ($evaluations[$candidate] === $evaluations[$best] && $candidate < $best)) {
            $best = $candidate;
        }
    }
    return $best;
}

function crossover(array $first, array $second, array $jobs, Minstd $rng): array
{
    $selected = [];
    foreach ($jobs as $job) {
        if ($rng->below(2) === 0) {
            $selected[$job->number] = true;
        }
    }
    $child = function (array $fixed, array $filling) use ($selected): array {
        $remaining = array_values(array_filter($filling, fn($gene) => !isset($selected[$gene])));
        $position = 0;
        return array_map(function ($gene) use ($selected, $remaining, &$position) {
            return isset($selected[$gene]) ? $gene : $remaining[$position++];
        }, $fixed);
    };
    return [$child($first, $second), $child($second, $first)];
}

function swapMutation(array &$chromosome, Minstd $rng): void
{
    $first = $rng->below(count($chromosome));
    $second = $rng->below(count($chromosome));
    [$chromosome[$first], $chromosome[$second]] = [$chromosome[$second], $chromosome[$first]];
}

function insertionMutation(array &$chromosome, Minstd $rng): void
{
    $first = $rng->below(count($chromosome));
    $second = $rng->below(count($chromosome));
    $gene = array_splice($chromosome, $first, 1);
    array_splice($chromosome, $second, 0, $gene);
}
