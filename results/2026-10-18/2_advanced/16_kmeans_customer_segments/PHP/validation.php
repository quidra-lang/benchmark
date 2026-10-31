<?php
namespace Segments;

function distance_table(array $points): array
{
    $table = array_fill(0, count($points), array_fill(0, count($points), 0.0));
    for ($i = 0; $i < count($points); $i++) for ($j = $i + 1; $j < count($points); $j++) {
        $table[$i][$j] = $table[$j][$i] = sqrt(squared_distance($points[$i], $points[$j]));
    }
    return $table;
}

function cluster_indices(array $points, array $solution, array $distances): array
{
    $k = $solution['k'];
    $silhouettes = $spreads = [];
    foreach ($points as $i => $point) {
        $own = $solution['labels'][$i];
        $size = count($solution['members'][$own]);
        if ($size === 1) {
            $silhouettes[] = 0.0;
            continue;
        }
        $totals = array_fill(0, $k, 0.0);
        foreach ($points as $j => $other) if ($i !== $j) $totals[$solution['labels'][$j]] += $distances[$i][$j];
        $inner = $totals[$own] / ($size - 1);
        $outer = null;
        for ($j = 0; $j < $k; $j++) if ($j !== $own) {
            $value = $totals[$j] / count($solution['members'][$j]);
            if ($outer === null || $value < $outer) $outer = $value;
        }
        $largest = max($inner, $outer);
        $silhouettes[] = $largest == 0 ? 0.0 : ($outer - $inner) / $largest;
    }
    $global = mean_point($points);
    $between = 0.0;
    foreach ($solution['members'] as $label => $members) {
        $between += count($members) * squared_distance($solution['centers'][$label], $global);
        $total = 0.0;
        foreach ($members as $index) $total += sqrt(squared_distance($points[$index], $solution['centers'][$label]));
        $spreads[] = $total / count($members);
    }
    $db = 0.0;
    for ($label = 0; $label < $k; $label++) {
        $worst = null;
        for ($other = 0; $other < $k; $other++) if ($other !== $label) {
            $value = ($spreads[$label] + $spreads[$other]) / sqrt(squared_distance($solution['centers'][$label], $solution['centers'][$other]));
            if ($worst === null || $value > $worst) $worst = $value;
        }
        $db += $worst;
    }
    return ['silhouettes' => $silhouettes, 'silhouette' => mean($silhouettes),
        'calinski_harabasz' => ($between / ($k - 1)) / ($solution['sse'] / (count($points) - $k)), 'davies_bouldin' => $db / $k];
}

function elbow(int $k, int $firstK, int $lastK, float $within, float $first, float $last): float
{
    $x = ($k - $firstK) / ($lastK - $firstK);
    $y = ($within - $last) / ($first - $last);
    return ((1 - $x) - $y) / sqrt(2);
}

function hartigan(float $within, float $following, int $n, int $k): float
{
    return ($within / $following - 1) * ($n - $k - 1);
}

function pair_count(int $size): int
{
    return intdiv($size * ($size - 1), 2);
}

function adjusted_rand(array $first, array $second): float
{
    $rows = $columns = $cells = [];
    foreach ($first as $index => $left) {
        $a = '#'.$left;
        $b = '#'.$second[$index];
        $rows[$a] = ($rows[$a] ?? 0) + 1;
        $columns[$b] = ($columns[$b] ?? 0) + 1;
        $cells[$a][$b] = ($cells[$a][$b] ?? 0) + 1;
    }
    $sx = $sy = $sxy = 0;
    foreach ($rows as $size) $sx += pair_count($size);
    foreach ($columns as $size) $sy += pair_count($size);
    foreach ($cells as $row) foreach ($row as $size) $sxy += pair_count($size);
    $z = pair_count(count($first));
    $numerator = 2 * ($z * $sxy - $sx * $sy);
    $denominator = $z * ($sx + $sy) - 2 * $sx * $sy;
    return $denominator === 0 ? 1.0 : $numerator / $denominator;
}
