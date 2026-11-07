<?php

function dispatch(object $instance, string $rule, ?array $genePositions = null): object
{
    $next = array_fill(0, count($instance->jobs), 0);
    $ready = $next;
    $free = array_fill(0, $instance->machineCount, 0);
    $order = array_fill(0, $instance->machineCount, []);
    $starts = $ends = array_fill(0, count($instance->operations), 0);
    $decisions = $ties = 0;
    for ($step = 0; $step < count($instance->operations); $step++) {
        $available = [];
        $earliest = $machine = null;
        foreach ($instance->jobs as $job) {
            if ($next[$job->index] === count($job->operations)) {
                continue;
            }
            $operation = $instance->operations[$job->operations[$next[$job->index]]];
            $start = max($ready[$job->index], $free[$operation->machine]);
            $end = $start + $operation->duration;
            $priority = match ($rule) {
                'SPT' => $operation->duration,
                'LPT' => -$operation->duration,
                'MWKR' => -($operation->duration + $operation->tail),
                'FIFO' => $ready[$job->index],
                'GENES' => $genePositions[$operation->index]
            };
            $available[] = (object) compact('operation', 'start', 'end', 'priority');
            if ($earliest === null || $end < $earliest || ($end === $earliest && $operation->machine < $machine)) {
                $earliest = $end;
                $machine = $operation->machine;
            }
        }
        $conflict = array_values(array_filter($available, fn($item) => $item->operation->machine === $machine && $item->start < $earliest));
        $chosen = $conflict[0];
        foreach ($conflict as $item) {
            if ($item->priority < $chosen->priority) {
                $chosen = $item;
            }
        }
        if (count($conflict) >= 2) {
            $decisions++;
        }
        if (count(array_filter($conflict, fn($item) => $item->priority === $chosen->priority)) >= 2) {
            $ties++;
        }
        $operation = $chosen->operation;
        $starts[$operation->index] = $chosen->start;
        $ends[$operation->index] = $chosen->end;
        $order[$machine][] = $operation->index;
        $ready[$operation->jobIndex] = $chosen->end;
        $free[$machine] = $chosen->end;
        $next[$operation->jobIndex]++;
    }
    $makespan = max($ends);
    return (object) compact('starts', 'ends', 'order', 'makespan', 'decisions', 'ties');
}
