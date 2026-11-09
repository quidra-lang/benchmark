<?php

function emptyTree(int $count): object
{
    return (object) ['count' => $count, 'next' => $count, 'adj' => [], 'negative' => 0];
}

function connect(object $tree, int $a, int $b, float $length = 0.0): void
{
    $tree->adj[$a][$b] = $length;
    $tree->adj[$b][$a] = $length;
}

function disconnect(object $tree, int $a, int $b): void
{
    unset($tree->adj[$a][$b], $tree->adj[$b][$a]);
}

function cloneTree(object $tree): object
{
    return clone $tree;
}

function star(array $taxa, int $count): object
{
    $tree = emptyTree($count);
    $root = $tree->next++;
    foreach ($taxa as $taxon) {
        connect($tree, $root, $taxon);
    }
    return $tree;
}

function leaves(object $tree): array
{
    $result = [];
    foreach ($tree->adj as $node => $edges) {
        if ($node < $tree->count) {
            $result[] = $node;
        }
    }
    sort($result, SORT_NUMERIC);
    return $result;
}

function bitCount(int $mask): int
{
    $count = 0;
    while ($mask !== 0) {
        $mask &= $mask - 1;
        $count++;
    }
    return $count;
}

function rootVisit(object $tree, object $rooted, int $node, ?int $parent): int
{
    $rooted->order[] = $node;
    $list = [];
    $mask = $node < $tree->count ? 1 << $node : 0;
    foreach ($tree->adj[$node] as $other => $length) {
        if ($other === $parent) {
            continue;
        }
        $rooted->parent[$other] = $node;
        $rooted->lengths[$other] = $length;
        $list[] = $other;
        $mask |= rootVisit($tree, $rooted, $other, $node);
    }
    $rooted->children[$node] = $list;
    $rooted->masks[$node] = $mask;
    return $mask;
}

function rootTree(object $tree, int $outgroup): object
{
    $root = array_key_first($tree->adj[$outgroup]);
    $rooted = (object) ['root' => $root, 'outgroup' => $outgroup, 'parent' => [$root => null], 'children' => [], 'masks' => [], 'lengths' => [], 'order' => [], 'ingroup' => 0];
    $all = rootVisit($tree, $rooted, $root, null);
    $rooted->ingroup = $all & ~(1 << $outgroup);
    $rooted->masks[$root] = $rooted->ingroup;
    return $rooted;
}

function splitSet(object $tree, int $outgroup): array
{
    $rooted = rootTree($tree, $outgroup);
    $splits = [];
    foreach ($rooted->order as $node) {
        if ($node >= $tree->count && $node !== $rooted->root) {
            $splits[$rooted->masks[$node]] = true;
        }
    }
    return $splits;
}

function neighborJoining(array $matrix, array $taxa, int $count): object
{
    $tree = emptyTree($count);
    $active = $taxa;
    $distances = [];
    foreach ($taxa as $i) {
        foreach ($taxa as $j) {
            $distances[$i][$j] = $matrix[$i][$j];
        }
    }
    while (count($active) >= 4) {
        $r = count($active);
        $totals = [];
        foreach ($active as $x) {
            $total = 0.0;
            foreach ($active as $y) {
                if ($y !== $x) {
                    $total += $distances[$x][$y];
                }
            }
            $totals[$x] = $total;
        }
        $chosen = null;
        for ($a = 0; $a < $r; $a++) {
            for ($b = $a + 1; $b < $r; $b++) {
                $i = $active[$a];
                $j = $active[$b];
                $q = ($r - 2) * $distances[$i][$j] - $totals[$i] - $totals[$j];
                if ($chosen === null || $q < $chosen->q) {
                    $chosen = (object) compact('i', 'j', 'q');
                }
            }
        }
        $i = $chosen->i;
        $j = $chosen->j;
        $u = $tree->next++;
        $first = $distances[$i][$j] / 2 + ($totals[$i] - $totals[$j]) / (2 * ($r - 2));
        connect($tree, $i, $u, $first);
        connect($tree, $j, $u, $distances[$i][$j] - $first);
        $active = array_values(array_filter($active, fn($k) => $k !== $i && $k !== $j));
        foreach ($active as $k) {
            $value = ($distances[$i][$k] + $distances[$j][$k] - $distances[$i][$j]) / 2;
            $distances[$u][$k] = $distances[$k][$u] = $value;
        }
        $active[] = $u;
    }
    [$a, $b, $c] = $active;
    $z = $tree->next++;
    connect($tree, $a, $z, ($distances[$a][$b] + $distances[$a][$c] - $distances[$b][$c]) / 2);
    connect($tree, $b, $z, ($distances[$a][$b] + $distances[$b][$c] - $distances[$a][$c]) / 2);
    connect($tree, $c, $z, ($distances[$a][$c] + $distances[$b][$c] - $distances[$a][$b]) / 2);
    foreach ($tree->adj as $node => $edges) {
        foreach ($edges as $other => $length) {
            if ($node < $other && $length < 0) {
                connect($tree, $node, $other, 0.0);
                $tree->negative++;
            }
        }
    }
    return $tree;
}

function pathVisit(object $tree, int $node, int $end, ?int $previous, array $lengths): ?array
{
    if ($node === $end) {
        return $lengths;
    }
    foreach ($tree->adj[$node] as $other => $length) {
        if ($other === $previous) {
            continue;
        }
        $next = $lengths;
        $next[] = $length;
        $found = pathVisit($tree, $other, $end, $node, $next);
        if ($found !== null) {
            return $found;
        }
    }
    return null;
}

function treePath(object $tree, int $start, int $end): array
{
    return pathVisit($tree, $start, $end, null, []);
}

function pathDistance(object $tree, int $start, int $end): float
{
    $total = 0.0;
    foreach (treePath($tree, $start, $end) as $length) {
        $total += $length;
    }
    return $total;
}

function patristic(object $tree): array
{
    $matrix = array_fill(0, $tree->count, array_fill(0, $tree->count, 0.0));
    $taxa = leaves($tree);
    for ($i = 0; $i < count($taxa); $i++) {
        for ($j = $i + 1; $j < count($taxa); $j++) {
            $a = $taxa[$i];
            $b = $taxa[$j];
            $matrix[$a][$b] = $matrix[$b][$a] = pathDistance($tree, $a, $b);
        }
    }
    return $matrix;
}
