<?php

function orderedChildren(array $merges, int $count): array
{
    $minimum = range(0, $count - 1);
    $children = [];
    foreach ($merges as $merge) {
        $children[] = $minimum[$merge->a] < $minimum[$merge->b] ? [$merge->a, $merge->b] : [$merge->b, $merge->a];
        $minimum[] = min($minimum[$merge->a], $minimum[$merge->b]);
    }
    return $children;
}

function leafOrder(array $children, int $count): array
{
    $order = [];
    $pending = [$count + count($children) - 1];
    while ($pending !== []) {
        $node = array_pop($pending);
        if ($node < $count) {
            $order[] = $node;
        } else {
            [$upper, $lower] = $children[$node - $count];
            $pending[] = $lower;
            $pending[] = $upper;
        }
    }
    return $order;
}

function heightColumn(float $height, float $maximum, int $width): int
{
    $position = $height / $maximum * $width;
    return $position >= $width + 1 ? $width + 1 : (int)floor($position);
}

function dendrogramRows(Tree $tree, array $idents, array $labels, float $maximum, array $cuts, int $width): array
{
    $count = $tree->count;
    $grid = array_fill(0, $count, array_fill(0, $width + 1, 0));
    $anchor = array_fill(0, 2 * $count - 1, 0);
    foreach ($tree->order as $row => $leaf) {
        $anchor[$leaf] = $row;
    }
    $mark = function ($row, $x, $level) use (&$grid) {
        $grid[$row][$x] = max($grid[$row][$x], $level);
    };
    foreach ($cuts as $x) {
        if ($x <= $width) {
            for ($row = 0; $row < $count; ++$row) {
                $mark($row, $x, 1);
            }
        }
    }
    $columns = array_map(fn($merge) => heightColumn($merge->height, $maximum, $width), $tree->merges);
    foreach ($tree->children as $step => [$upper, $lower]) {
        $x = $columns[$step];
        $mark($anchor[$upper], $x, 4);
        $mark($anchor[$lower], $x, 4);
        for ($row = $anchor[$upper] + 1; $row < $anchor[$lower]; ++$row) {
            $mark($row, $x, 3);
        }
        foreach ([$upper, $lower] as $child) {
            $start = $child < $count ? 0 : $columns[$child - $count] + 1;
            for ($position = $start; $position < $x; ++$position) {
                $mark($anchor[$child], $position, 2);
            }
        }
        $anchor[$count + $step] = intdiv($anchor[$upper] + $anchor[$lower], 2);
    }
    $idWidth = max(array_map('strlen', $idents));
    $labelWidth = max(array_map('strlen', $labels));
    $marks = ' :-|+';
    $rows = [];
    foreach ($tree->order as $row => $leaf) {
        $cells = implode('', array_map(fn($level) => $marks[$level], $grid[$row]));
        $rows[] = rtrim(str_pad($idents[$leaf], $idWidth) . ' ' . str_pad($labels[$leaf], $labelWidth) . ' ' . $cells, ' ');
    }
    $scale = '';
    for ($x = 0; $x <= $width; ++$x) {
        $scale .= $x % 10 === 0 ? '+' : '-';
    }
    $rows[] = str_repeat(' ', $idWidth + $labelWidth + 2) . $scale;
    return $rows;
}
