<?php

function radiusSquared($a, $b, $c, $area2)
{
    $first = (float)d2($a, $b);
    $second = (float)d2($b, $c);
    $third = (float)d2($c, $a);
    $area = (float)$area2;
    return (($first * $second) * $third) / ((4.0 * $area) * $area);
}

function vertexPosition($vertex, $hull, $points)
{
    $on = false;
    foreach ($hull as $i => $site) {
        $a = $points[$site];
        $b = $points[$hull[($i + 1) % count($hull)]];
        $value = ($b['x'] - $a['x']) * ($vertex['Y'] - $a['y'] * $vertex['D']) -
            ($b['y'] - $a['y']) * ($vertex['X'] - $a['x'] * $vertex['D']);
        if ($value < 0) {
            return 'outside';
        }
        if ($value === 0) {
            $on = true;
        }
    }
    return $on ? 'on' : 'inside';
}

function neighborOrder($site, $neighbors, $next, $mesh)
{
    $first = $next[$site] ?? min($neighbors);
    $order = [];
    $current = $first;
    do {
        $order[] = $current;
        $current = $mesh->directed[keyOf($site, $current)] ?? null;
    } while ($current !== null && $current !== $first);
    return $order;
}

function outward($u, $v, $points)
{
    return direction($points[$u], $points[$v]);
}

function boundedArea($site, $sequence, $vertices)
{
    $local = [];
    foreach ($sequence as $number) {
        $vertex = $vertices[$number - 1];
        $local[] = ['x' => $vertex['X'] / $vertex['D'] - $site['x'],
            'y' => $vertex['Y'] / $vertex['D'] - $site['y']];
    }
    $twice = 0.0;
    foreach ($local as $i => $a) {
        $b = $local[($i + 1) % count($local)];
        $twice += $a['x'] * $b['y'] - $b['x'] * $a['y'];
    }
    return $twice / 2;
}

function clippedArea($site, $neighbors, $points)
{
    $polygon = [['x' => 0.0, 'y' => 0.0], ['x' => 1000.0, 'y' => 0.0],
        ['x' => 1000.0, 'y' => 1000.0], ['x' => 0.0, 'y' => 1000.0]];
    foreach ($neighbors as $number) {
        $other = $points[$number];
        $c1 = 2 * ($other['x'] - $site['x']);
        $c2 = 2 * ($other['y'] - $site['y']);
        $c3 = $other['x'] * $other['x'] + $other['y'] * $other['y'] - $site['x'] * $site['x'] - $site['y'] * $site['y'];
        $f = fn($p) => $c1 * $p['x'] + $c2 * $p['y'] - $c3;
        $next = [];
        foreach ($polygon as $i => $p) {
            $q = $polygon[($i + 1) % count($polygon)];
            $fp = $f($p);
            $fq = $f($q);
            if ($fp <= 0) {
                $next[] = $p;
            }
            if (($fp < 0 && $fq > 0) || ($fq < 0 && $fp > 0)) {
                $lambda = $fp / ($fp - $fq);
                $next[] = ['x' => $p['x'] + ($q['x'] - $p['x']) * $lambda,
                    'y' => $p['y'] + ($q['y'] - $p['y']) * $lambda];
            }
        }
        $polygon = $next;
    }
    $twice = 0.0;
    foreach ($polygon as $i => $p) {
        $q = $polygon[($i + 1) % count($polygon)];
        $twice += $p['x'] * $q['y'] - $q['x'] * $p['y'];
    }
    return $twice / 2;
}
