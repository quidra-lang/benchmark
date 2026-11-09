<?php
namespace Segments;

function squared_distance(array $first, array $second): float
{
    $total = 0.0;
    foreach ($first as $feature => $value) {
        $difference = $value - $second[$feature];
        $total += $difference * $difference;
    }
    return $total;
}

function mean_point(array $points): array
{
    $totals = array_fill(0, count($points[0]), 0.0);
    foreach ($points as $point) foreach ($point as $feature => $value) $totals[$feature] += $value;
    return array_map(fn($total) => $total / count($points), $totals);
}

function cluster_groups(array $labels, int $k): array
{
    $groups = array_fill(0, $k, []);
    foreach ($labels as $index => $label) $groups[$label][] = $index;
    return $groups;
}

function cluster_center(array $points, array $labels, int $label): array
{
    $members = [];
    foreach ($points as $index => $point) if ($labels[$index] === $label) $members[] = $point;
    return mean_point($members);
}

function cluster_centers(array $points, array $labels, int $k): array
{
    $centers = [];
    for ($label = 0; $label < $k; $label++) $centers[] = cluster_center($points, $labels, $label);
    return $centers;
}

function assign(array $points, array $centers): array
{
    $labels = $errors = [];
    foreach ($points as $point) {
        $chosen = 0;
        $best = squared_distance($point, $centers[0]);
        for ($label = 1; $label < count($centers); $label++) {
            $distance = squared_distance($point, $centers[$label]);
            if ($distance < $best) [$chosen, $best] = [$label, $distance];
        }
        $labels[] = $chosen;
        $errors[] = $best;
    }
    return [$labels, $errors];
}

function refill(array &$labels, array &$errors, int $k): int
{
    $sizes = array_fill(0, $k, 0);
    foreach ($labels as $label) $sizes[$label]++;
    $reseeds = 0;
    for ($label = 0; $label < $k; $label++) {
        if ($sizes[$label] > 0) continue;
        $chosen = -1;
        foreach ($labels as $index => $current) {
            if ($sizes[$current] >= 2 && ($chosen < 0 || $errors[$index] > $errors[$chosen])) $chosen = $index;
        }
        $sizes[$labels[$chosen]]--;
        $sizes[$label]++;
        $labels[$chosen] = $label;
        $errors[$chosen] = 0.0;
        $reseeds++;
    }
    return $reseeds;
}

function sum_squared(array $points, array $labels, array $centers): float
{
    $total = 0.0;
    foreach ($points as $index => $point) $total += squared_distance($point, $centers[$labels[$index]]);
    return $total;
}

function lloyd(array $points, array $initial, int $limit): array
{
    [$labels, $errors] = assign($points, $initial);
    $iterations = $reseeds = 0;
    $converged = false;
    while ($iterations < $limit) {
        $reseeds += refill($labels, $errors, count($initial));
        $centers = cluster_centers($points, $labels, count($initial));
        $iterations++;
        [$updated, $errors] = assign($points, $centers);
        $converged = $updated === $labels;
        $labels = $updated;
        if ($converged) break;
    }
    $reseeds += refill($labels, $errors, count($initial));
    $centers = cluster_centers($points, $labels, count($initial));
    return ['labels' => $labels, 'centers' => $centers, 'iterations' => $iterations,
        'reseeds' => $reseeds, 'converged' => $converged, 'sse' => sum_squared($points, $labels, $centers)];
}
