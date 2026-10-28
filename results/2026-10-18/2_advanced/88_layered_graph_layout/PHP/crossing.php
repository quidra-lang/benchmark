<?php

function positions(array $orders): array
{
    $position = [];
    foreach ($orders as $layer)
        foreach ($layer as $i => $v)
            $position[$v] = $i;
    return $position;
}

function accumulator(array $segments, array $position, int $lowerSize): int
{
    $capacity = 1;
    while ($capacity < $lowerSize)
        $capacity *= 2;
    $tree = array_fill(0, (2 * $capacity) - 1, 0);
    $count = 0;
    $pairs = array_map(fn($s) => [$position[$s[0]], $position[$s[1]]], $segments);
    usort($pairs, fn($a, $b) => $a <=> $b);
    foreach ($pairs as [$upper, $lower]) {
        $i = $lower + $capacity - 1;
        ++$tree[$i];
        while ($i > 0) {
            if (($i % 2) === 1)
                $count += $tree[$i + 1];
            $i = intdiv($i - 1, 2);
            ++$tree[$i];
        }
    }
    return $count;
}

function bruteForce(array $segments, array $position): int
{
    $count = 0;
    foreach ($segments as $i => $a)
        for ($j = $i + 1; $j < count($segments); ++$j) {
            $b = $segments[$j];
            if ((($position[$a[0]] - $position[$b[0]]) * ($position[$a[1]] - $position[$b[1]])) < 0)
                ++$count;
        }
    return $count;
}

function gapCounts(array $gaps, array $orders): array
{
    $position = positions($orders);
    $counts = [];
    foreach ($gaps as $i => $segments)
        $counts[] = accumulator($segments, $position, count($orders[$i + 1]));
    return $counts;
}

function totalCrossings(array $gaps, array $orders): int
{
    return array_sum(gapCounts($gaps, $orders));
}

function localCost(array $gaps, array $orders, int $layer): int
{
    $position = positions($orders);
    $cost = 0;
    foreach ([$layer - 1, $layer] as $i)
        if (isset($gaps[$i]))
            $cost += accumulator($gaps[$i], $position, count($orders[$i + 1]));
    return $cost;
}

function adjacentCost(int $a, int $b, array $upper, array $lower, array $position): int
{
    $cost = 0;
    foreach ([$upper, $lower] as $neighbors)
        foreach ($neighbors[$a] as $x)
            foreach ($neighbors[$b] as $y)
                $cost += (int) ($position[$x] > $position[$y]);
    return $cost;
}
