<?php

function lineClass(object $line): int
{
    if ($line->last) return 1;
    if ($line->slack <= 1) return 0;
    if ($line->slack <= 3) return 1;
    if ($line->slack <= 6) return 2;
    return 3;
}

function lineCost(object $problem, object $line, int $previousClass, array $parameters): int
{
    $cost = $parameters['line_penalty'];
    $cost += $line->slack < 0 ? $parameters['overfull_penalty'] : ($line->last ? 0 : $line->slack * $line->slack);
    if ($problem->points[$line->b]->mid) {
        $cost += $parameters['hyphen_penalty'];
        if ($problem->points[$line->a]->mid) {
            $cost += $parameters['double_hyphen_demerit'];
        }
    }
    if ($line->last && $problem->points[$line->a]->mid) {
        $cost += $parameters['final_hyphen_demerit'];
    }
    if (abs(lineClass($line) - $previousClass) >= 2) {
        $cost += $parameters['fitness_demerit'];
    }
    return $cost;
}

function breakingCost(object $problem, array $breaks, array $parameters): int
{
    $total = 0;
    $previous = 0;
    $previousClass = 1;
    foreach ($breaks as $end) {
        $line = ($problem->measure)($previous, $end);
        $total += lineCost($problem, $line, $previousClass, $parameters);
        $previousClass = lineClass($line);
        $previous = $end;
    }
    return $total;
}

function optimal(object $problem, array $parameters): object
{
    $end = count($problem->points) - 1;
    $table = array_fill(0, $end + 1, array_fill(0, 4, null));
    $table[0][1] = (object) ['cost' => 0];
    for ($b = 1; $b <= $end; $b++) {
        $consider = function ($a, $line) use ($problem, $parameters, &$table, $b) {
            if ($line->slack < 0 && $b !== $a + 1) {
                return;
            }
            $currentClass = lineClass($line);
            for ($previousClass = 0; $previousClass < 4; $previousClass++) {
                $earlier = $table[$a][$previousClass];
                if ($earlier === null) {
                    continue;
                }
                $cost = $earlier->cost + lineCost($problem, $line, $previousClass, $parameters);
                $best = $table[$b][$currentClass];
                if ($best === null || $cost < $best->cost || ($cost === $best->cost && ($a < $best->a || ($a === $best->a && $previousClass < $best->previousClass)))) {
                    $table[$b][$currentClass] = (object) compact('cost', 'a', 'previousClass');
                }
            }
        };
        $consider(0, ($problem->measure)(0, $b));
        for ($a = $b - 1; $a >= 1; $a--) {
            $line = ($problem->measure)($a, $b);
            if ($line->slack < 0 && $b !== $a + 1) {
                break;
            }
            $consider($a, $line);
        }
    }
    $breaks = [];
    $position = $end;
    $currentClass = 1;
    while ($position > 0) {
        $breaks[] = $position;
        $previous = $table[$position][$currentClass];
        $position = $previous->a;
        $currentClass = $previous->previousClass;
    }
    return (object) ['breaks' => array_reverse($breaks), 'cost' => $table[$end][1]->cost];
}

function greedy(object $problem, array $parameters): object
{
    $end = count($problem->points) - 1;
    $breaks = [];
    $start = 0;
    while ($start < $end) {
        $selected = $start + 1;
        if (($problem->measure)($start, $selected)->slack >= 0) {
            for ($candidate = $selected + 1; $candidate <= $end; $candidate++) {
                if (($problem->measure)($start, $candidate)->slack < 0) {
                    break;
                }
                $selected = $candidate;
            }
        }
        $breaks[] = $selected;
        $start = $selected;
    }
    return (object) ['breaks' => $breaks, 'cost' => breakingCost($problem, $breaks, $parameters)];
}
