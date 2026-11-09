<?php
namespace LinkAnalysis;

function strong_components(array $adjacency): array
{
    $n = count($adjacency);
    $order = array_fill(0, $n, -1);
    $low = array_fill(0, $n, 0);
    $onStack = array_fill(0, $n, false);
    $stack = $groups = [];
    $counter = 0;
    for ($root = 0; $root < $n; $root++) {
        if ($order[$root] !== -1) continue;
        $order[$root] = $low[$root] = $counter++;
        $stack[] = $root;
        $onStack[$root] = true;
        $work = [[$root, 0]];
        while ($work) {
            $last = count($work) - 1;
            [$node, $position] = $work[$last];
            if ($position < count($adjacency[$node])) {
                $work[$last][1]++;
                $child = $adjacency[$node][$position];
                if ($order[$child] === -1) {
                    $order[$child] = $low[$child] = $counter++;
                    $stack[] = $child;
                    $onStack[$child] = true;
                    $work[] = [$child, 0];
                } elseif ($onStack[$child]) $low[$node] = min($low[$node], $order[$child]);
                continue;
            }
            array_pop($work);
            if ($work) {
                $parent = $work[count($work) - 1][0];
                $low[$parent] = min($low[$parent], $low[$node]);
            }
            if ($low[$node] === $order[$node]) {
                $group = [];
                do {
                    $member = array_pop($stack);
                    $onStack[$member] = false;
                    $group[] = $member;
                } while ($member !== $node);
                $groups[] = $group;
            }
        }
    }
    return $groups;
}

function reachable(array $adjacency, array $starts): array
{
    $seen = array_fill(0, count($adjacency), false);
    $stack = [];
    foreach ($starts as $node) if (!$seen[$node]) {
        $seen[$node] = true;
        $stack[] = $node;
    }
    while ($stack) foreach ($adjacency[array_pop($stack)] as $neighbor) if (!$seen[$neighbor]) {
        $seen[$neighbor] = true;
        $stack[] = $neighbor;
    }
    return $seen;
}

function bfs_distances(array $adjacency, array $starts): array
{
    $distances = array_fill(0, count($adjacency), -1);
    $queue = [];
    foreach ($starts as $node) if ($distances[$node] === -1) {
        $distances[$node] = 0;
        $queue[] = $node;
    }
    for ($head = 0; $head < count($queue); $head++) {
        $node = $queue[$head];
        foreach ($adjacency[$node] as $neighbor) if ($distances[$neighbor] === -1) {
            $distances[$neighbor] = $distances[$node] + 1;
            $queue[] = $neighbor;
        }
    }
    return $distances;
}

function weak_components(array $neighbors): array
{
    $labels = array_fill(0, count($neighbors), -1);
    $count = 0;
    foreach ($neighbors as $start => $group) {
        if ($labels[$start] !== -1) continue;
        $labels[$start] = $count;
        $stack = [$start];
        while ($stack) foreach ($neighbors[array_pop($stack)] as $neighbor) if ($labels[$neighbor] === -1) {
            $labels[$neighbor] = $count;
            $stack[] = $neighbor;
        }
        $count++;
    }
    return $labels;
}
