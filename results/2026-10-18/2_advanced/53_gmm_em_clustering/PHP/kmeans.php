<?php

function squaredDistance($first, $second) {
    $dx = $first['x'] - $second['x'];
    $dy = $first['y'] - $second['y'];
    return $dx * $dx + $dy * $dy;
}

function pointDistance($first, $second) {
    return sqrt(squaredDistance($first, $second));
}

function assignCenters($points, $centers) {
    $assignment = [];
    foreach ($points as $point) {
        $cluster = 0;
        $best = squaredDistance($point, $centers[0]);
        for ($k = 1; $k < count($centers); $k++) {
            $value = squaredDistance($point, $centers[$k]);
            if ($value < $best) {
                $cluster = $k;
                $best = $value;
            }
        }
        $assignment[] = $cluster;
    }
    return $assignment;
}

function updateCenters($points, $assignment, $centers) {
    $sums = array_fill(0, count($centers), ['x' => 0.0, 'y' => 0.0, 'count' => 0]);
    foreach ($points as $i => $point) {
        $k = $assignment[$i];
        $sums[$k]['x'] += $point['x'];
        $sums[$k]['y'] += $point['y'];
        $sums[$k]['count']++;
    }
    foreach ($sums as $k => $sum) if ($sum['count']) $centers[$k] = ['x' => $sum['x'] / $sum['count'], 'y' => $sum['y'] / $sum['count']];
    return $centers;
}

function kmeansFit($points, $initial, $maximumIterations) {
    $centers = [];
    foreach ($initial as $component) $centers[] = ['x' => $component['mx'], 'y' => $component['my']];
    $assignment = assignCenters($points, $centers);
    $iterations = 0;
    for ($t = 1; $t <= $maximumIterations; $t++) {
        $centers = updateCenters($points, $assignment, $centers);
        $next = assignCenters($points, $centers);
        $stable = $next === $assignment;
        $assignment = $next;
        $iterations = $t;
        if ($stable) break;
    }
    $inertia = 0.0;
    $sizes = array_fill(0, count($centers), 0);
    foreach ($points as $i => $point) {
        $sizes[$assignment[$i]]++;
        $inertia += squaredDistance($point, $centers[$assignment[$i]]);
    }
    return compact('centers', 'assignment', 'iterations', 'inertia', 'sizes');
}
