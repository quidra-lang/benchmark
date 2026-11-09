<?php

function minimumMatching($costs)
{
    $rows = count($costs);
    $columns = $rows === 0 ? 0 : count($costs[0]);
    if ($rows === 0 || $columns === 0) {
        return [];
    }
    $transposed = $rows > $columns;
    $values = $transposed ? matTranspose($costs) : $costs;
    $n = count($values);
    $m = count($values[0]);
    $u = array_fill(0, $n + 1, 0.0);
    $v = array_fill(0, $m + 1, 0.0);
    $owner = $way = array_fill(0, $m + 1, 0);
    for ($row = 1; $row <= $n; $row++) {
        $owner[0] = $row;
        $column = 0;
        $slack = array_fill(0, $m + 1, INF);
        $used = array_fill(0, $m + 1, false);
        do {
            $used[$column] = true;
            $current = $owner[$column];
            $delta = INF;
            $next = 0;
            for ($j = 1; $j <= $m; $j++) {
                if ($used[$j]) {
                    continue;
                }
                $reduced = $values[$current - 1][$j - 1] - $u[$current] - $v[$j];
                if ($reduced < $slack[$j]) {
                    $slack[$j] = $reduced;
                    $way[$j] = $column;
                }
                if ($slack[$j] < $delta) {
                    $delta = $slack[$j];
                    $next = $j;
                }
            }
            for ($j = 0; $j <= $m; $j++) {
                if ($used[$j]) {
                    $u[$owner[$j]] += $delta;
                    $v[$j] -= $delta;
                } else {
                    $slack[$j] -= $delta;
                }
            }
            $column = $next;
        } while ($owner[$column] !== 0);
        do {
            $previous = $way[$column];
            $owner[$column] = $owner[$previous];
            $column = $previous;
        } while ($column !== 0);
    }
    $pairs = [];
    for ($j = 1; $j <= $m; $j++) {
        if ($owner[$j] !== 0) {
            $pairs[] = $transposed ? [$j - 1, $owner[$j] - 1] : [$owner[$j] - 1, $j - 1];
        }
    }
    usort($pairs, fn($a, $b) => $a[0] <=> $b[0]);
    return $pairs;
}

function optimalAssignment($costs)
{
    if (count($costs) === 0 || count($costs[0]) === 0) {
        return [];
    }
    $maximum = 0.0;
    foreach ($costs as $row) {
        foreach ($row as $cost) {
            if ($cost !== null) {
                $maximum = max($maximum, $cost);
            }
        }
    }
    $penalty = ($maximum + 1) * (min(count($costs), count($costs[0])) + 1);
    $filled = [];
    foreach ($costs as $row) {
        $filled[] = array_map(fn($cost) => $cost === null ? $penalty : $cost, $row);
    }
    return array_values(array_filter(minimumMatching($filled), fn($pair) => $costs[$pair[0]][$pair[1]] !== null));
}
