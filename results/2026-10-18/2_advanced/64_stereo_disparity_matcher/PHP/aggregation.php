<?php

const DIRECTIONS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [-1, 1], [1, -1]];

function pathCosts(array $base, array $left, int $width, int $height, array $direction, int $p1, int $p2, int $gamma): array
{
    [$rx, $ry] = $direction;
    $result = array_fill(0, count($base), []);
    $disparities = count($base[0]);
    for ($row = 0; $row < $height; $row++) {
        $y = $ry >= 0 ? $row : $height - 1 - $row;
        for ($column = 0; $column < $width; $column++) {
            $x = $rx >= 0 ? $column : $width - 1 - $column;
            $p = $y * $width + $x;
            $qx = $x - $rx;
            $qy = $y - $ry;
            if ($qx < 0 || $qx >= $width || $qy < 0 || $qy >= $height) {
                $result[$p] = $base[$p];
                continue;
            }
            $q = $qy * $width + $qx;
            $previous = $result[$q];
            $minimum = min($previous);
            $penalty = max($p1, intdiv($p2 * $gamma, $gamma + abs($left[$p] - $left[$q])));
            $result[$p] = [];
            for ($d = 0; $d < $disparities; $d++) {
                $best = min($previous[$d], $minimum + $penalty);
                if ($d > 0) $best = min($best, $previous[$d - 1] + $p1);
                if ($d + 1 < $disparities) $best = min($best, $previous[$d + 1] + $p1);
                $result[$p][] = $base[$p][$d] + $best - $minimum;
            }
        }
    }
    return $result;
}

function cumulativeCosts(array $base, array $left, int $width, int $height, int $paths, int $p1, int $p2, int $gamma): Generator
{
    $total = array_fill(0, count($base), array_fill(0, count($base[0]), 0));
    for ($i = 0; $i < $paths; $i++) {
        $costs = pathCosts($base, $left, $width, $height, DIRECTIONS[$i], $p1, $p2, $gamma);
        foreach ($costs as $p => $row) foreach ($row as $d => $value) $total[$p][$d] += $value;
        yield $total;
    }
}
