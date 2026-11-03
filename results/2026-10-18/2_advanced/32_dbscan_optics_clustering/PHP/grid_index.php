<?php

function squaredDistance(object $first, object $second): int
{
    $x = $first->x - $second->x;
    $y = $first->y - $second->y;
    return $x * $x + $y * $y;
}

function distanceAt(array $distances, int $p, int $q): int
{
    return unpack('V', $distances[$p], 4 * $q)[1];
}

function buildGrid(array $points, int $radius, array $distances): object
{
    $cells = [];
    $locations = [];
    foreach ($points as $p => $point) {
        $gx = intdiv($point->x, $radius);
        $gy = intdiv($point->y, $radius);
        $locations[] = [$gx, $gy];
        $key = $gx . ',' . $gy;
        if (!isset($cells[$key])) {
            $cells[$key] = (object) ['gx' => $gx, 'gy' => $gy, 'points' => []];
        }
        $cells[$key]->points[] = $p;
    }
    $busiest = null;
    $occupancy = [];
    foreach ($cells as $cell) {
        $count = count($cell->points);
        $occupancy[$count] = ($occupancy[$count] ?? 0) + 1;
        if ($busiest === null || $count > count($busiest->points) ||
            ($count === count($busiest->points) && ($cell->gy < $busiest->gy || ($cell->gy === $busiest->gy && $cell->gx < $busiest->gx)))) {
            $busiest = $cell;
        }
    }
    $candidates = $neighborTotal = $bruteTotal = 0;
    $matches = true;
    $neighborhoods = $candidateCounts = [];
    foreach ($points as $p => $_) {
        [$gx, $gy] = $locations[$p];
        $neighbors = [];
        $count = 0;
        for ($row = $gy - 1; $row <= $gy + 1; $row++) {
            for ($column = $gx - 1; $column <= $gx + 1; $column++) {
                $cell = $cells[$column . ',' . $row] ?? null;
                if ($cell === null) {
                    continue;
                }
                foreach ($cell->points as $q) {
                    $count++;
                    if (distanceAt($distances, $p, $q) <= $radius * $radius) {
                        $neighbors[] = $q;
                    }
                }
            }
        }
        $brute = 0;
        foreach ($points as $q => $_) {
            $brute += (int) (distanceAt($distances, $p, $q) <= $radius * $radius);
        }
        if ($brute !== count($neighbors)) {
            $matches = false;
        }
        $neighborhoods[] = $neighbors;
        $candidateCounts[] = $count;
        $candidates += $count;
        $neighborTotal += count($neighbors);
        $bruteTotal += $brute;
    }
    return (object) ['radius' => $radius, 'neighborhoods' => $neighborhoods, 'candidateCounts' => $candidateCounts,
        'cells' => count($cells), 'busiest' => $busiest, 'occupancy' => $occupancy, 'candidates' => $candidates,
        'pairs' => intdiv($neighborTotal - count($points), 2), 'brutePairs' => intdiv($bruteTotal - count($points), 2), 'matches' => $matches];
}
