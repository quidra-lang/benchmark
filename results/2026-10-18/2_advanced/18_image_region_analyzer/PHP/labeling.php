<?php
declare(strict_types=1);

namespace ImageRegions;

const PREVIOUS_NEIGHBORS = [
    4 => [[-1, 0], [0, -1]],
    8 => [[-1, 0], [-1, -1], [0, -1], [1, -1]],
];

final class Labeling
{
    public function __construct(public array $labels, public int $count, public int $provisional) {}
}

function findRoot(array &$parents, int $label): int
{
    while ($parents[$label] !== $label) {
        $parents[$label] = $parents[$parents[$label]];
        $label = $parents[$label];
    }
    return $label;
}

function unite(array &$parents, int $first, int $second): void
{
    $a = findRoot($parents, $first);
    $b = findRoot($parents, $second);
    if ($a !== $b) {
        $parents[max($a, $b)] = min($a, $b);
    }
}

function labelComponents(array $mask, int $connectivity): Labeling
{
    $height = count($mask);
    $width = count($mask[0]);
    $provisional = array_fill(0, $height, array_fill(0, $width, 0));
    $parents = [0];
    for ($y = 0; $y < $height; $y++) {
        for ($x = 0; $x < $width; $x++) {
            if (!$mask[$y][$x]) {
                continue;
            }
            $neighbors = [];
            foreach (PREVIOUS_NEIGHBORS[$connectivity] as [$dx, $dy]) {
                $nx = $x + $dx;
                $ny = $y + $dy;
                if ($nx >= 0 && $nx < $width && $ny >= 0 && $mask[$ny][$nx]) {
                    $neighbors[] = $provisional[$ny][$nx];
                }
            }
            if ($neighbors === []) {
                $provisional[$y][$x] = count($parents);
                $parents[] = count($parents);
            } else {
                $provisional[$y][$x] = $neighbors[0];
                foreach (array_slice($neighbors, 1) as $other) {
                    unite($parents, $neighbors[0], $other);
                }
            }
        }
    }
    $numbers = [];
    $labels = array_fill(0, $height, array_fill(0, $width, 0));
    $count = 0;
    for ($y = 0; $y < $height; $y++) {
        for ($x = 0; $x < $width; $x++) {
            if ($provisional[$y][$x] === 0) {
                continue;
            }
            $root = findRoot($parents, $provisional[$y][$x]);
            if (!isset($numbers[$root])) {
                $numbers[$root] = ++$count;
            }
            $labels[$y][$x] = $numbers[$root];
        }
    }
    return new Labeling($labels, $count, count($parents) - 1);
}

function bitQuadEuler(array $mask, int $connectivity): int
{
    $singles = $triples = $diagonals = 0;
    for ($y = -1; $y < count($mask); $y++) {
        for ($x = -1; $x < count($mask[0]); $x++) {
            $a = occupied($mask, $x, $y);
            $b = occupied($mask, $x + 1, $y);
            $c = occupied($mask, $x, $y + 1);
            $d = occupied($mask, $x + 1, $y + 1);
            $count = (int)$a + (int)$b + (int)$c + (int)$d;
            if ($count === 1) {
                $singles++;
            } elseif ($count === 3) {
                $triples++;
            } elseif ($count === 2 && ($a && $d || $b && $c)) {
                $diagonals++;
            }
        }
    }
    return intdiv($singles - $triples + ($connectivity === 8 ? -2 : 2) * $diagonals, 4);
}
