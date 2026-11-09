<?php

class DisjointSet
{
    public $parent;
    public $sizes;
    public $count;

    public function __construct($size)
    {
        $this->parent = range(0, $size);
        $this->sizes = array_fill(0, $size + 1, 1);
        $this->count = $size;
    }

    public function find($site)
    {
        if ($this->parent[$site] !== $site) {
            $this->parent[$site] = $this->find($this->parent[$site]);
        }
        return $this->parent[$site];
    }

    public function union($a, $b)
    {
        $first = $this->find($a);
        $second = $this->find($b);
        if ($first === $second) {
            return false;
        }
        if ($this->sizes[$first] < $this->sizes[$second]) {
            [$first, $second] = [$second, $first];
        }
        $this->parent[$second] = $first;
        $this->sizes[$first] += $this->sizes[$second];
        $this->count--;
        return true;
    }
}

function nearestNeighbors($points, $neighbors)
{
    $result = [null];
    for ($site = 1; $site < count($points); $site++) {
        $nearest = $neighbors[$site][0];
        foreach ($neighbors[$site] as $other) {
            $distance = d2($points[$site], $points[$other]);
            $best = d2($points[$site], $points[$nearest]);
            if ($distance < $best || ($distance === $best && $other < $nearest)) {
                $nearest = $other;
            }
        }
        $result[] = $nearest;
    }
    return $result;
}

function nearestComponents($nearest)
{
    $sets = new DisjointSet(count($nearest) - 1);
    for ($site = 1; $site < count($nearest); $site++) {
        $sets->union($site, $nearest[$site]);
    }
    $groups = [];
    for ($site = 1; $site < count($nearest); $site++) {
        $root = $sets->find($site);
        $groups[$root][] = $site;
    }
    $groups = array_values($groups);
    usort($groups, fn($a, $b) => $a[0] <=> $b[0]);
    return $groups;
}

function minimumTree($edges, $size)
{
    $sorted = $edges;
    usort($sorted, fn($a, $b) => ($a['length2'] <=> $b['length2']) ?:
        (($a['i'] <=> $b['i']) ?: ($a['j'] <=> $b['j'])));
    $sets = new DisjointSet($size);
    $adopted = [];
    foreach ($sorted as $edge) {
        if ($sets->union($edge['i'], $edge['j'])) {
            $adopted[] = $edge;
        }
    }
    return $adopted;
}

function gabriel($edge, $mesh, $points)
{
    $opposites = [$mesh->directed[keyOf($edge['i'], $edge['j'])] ?? null,
        $mesh->directed[keyOf($edge['j'], $edge['i'])] ?? null];
    foreach ($opposites as $site) {
        if ($site !== null && dot($points[$site], $points[$edge['i']], $points[$edge['j']]) <= 0) {
            return false;
        }
    }
    return true;
}

function relativeNeighborhood($edge, $points)
{
    for ($site = 1; $site < count($points); $site++) {
        if (d2($points[$edge['i']], $points[$site]) < $edge['length2'] &&
            d2($points[$edge['j']], $points[$site]) < $edge['length2']) {
            return false;
        }
    }
    return true;
}

function greedyRoute($start, $end, $neighbors, $points)
{
    $path = [$start];
    $current = $start;
    $length = 0.0;
    while ($current !== $end) {
        $next = $neighbors[$current][0];
        foreach ($neighbors[$current] as $other) {
            $distance = d2($points[$other], $points[$end]);
            $best = d2($points[$next], $points[$end]);
            if ($distance < $best || ($distance === $best && $other < $next)) {
                $next = $other;
            }
        }
        $length += sqrt(d2($points[$current], $points[$next]));
        $current = $next;
        $path[] = $current;
    }
    return ['path' => $path, 'length' => $length];
}

function dijkstra($start, $neighbors, $points)
{
    $distances = array_fill(0, count($points), INF);
    $previous = array_fill(0, count($points), null);
    $visited = array_fill(0, count($points), false);
    $distances[$start] = 0.0;
    for ($step = 1; $step < count($points); $step++) {
        $current = null;
        for ($site = 1; $site < count($points); $site++) {
            if (!$visited[$site] && ($current === null || $distances[$site] < $distances[$current])) {
                $current = $site;
            }
        }
        $visited[$current] = true;
        foreach ($neighbors[$current] as $other) {
            if ($visited[$other]) {
                continue;
            }
            $length = $distances[$current] + sqrt(d2($points[$current], $points[$other]));
            if ($length < $distances[$other]) {
                $distances[$other] = $length;
                $previous[$other] = $current;
            }
        }
    }
    return ['distances' => $distances, 'previous' => $previous];
}
