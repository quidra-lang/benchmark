<?php

function difference(array $a, array $b): array
{
    return [$a[0] - $b[0], $a[1] - $b[1], $a[2] - $b[2]];
}

function vectorAdd(array $a, array $b): array
{
    return [$a[0] + $b[0], $a[1] + $b[1], $a[2] + $b[2]];
}

function dot(array $a, array $b): int
{
    return $a[0] * $b[0] + $a[1] * $b[1] + $a[2] * $b[2];
}

function cross(array $a, array $b): array
{
    return [$a[1] * $b[2] - $a[2] * $b[1], $a[2] * $b[0] - $a[0] * $b[2], $a[0] * $b[1] - $a[1] * $b[0]];
}

function normal(array $face, array $vertices): array
{
    [$a, $b, $c] = array_map(fn($v) => $vertices[$v], $face['vertices']);
    return cross(difference($b, $a), difference($c, $a));
}

function determinant(array $face, array $vertices): int
{
    [$a, $b, $c] = array_map(fn($v) => $vertices[$v], $face['vertices']);
    return dot($a, cross($b, $c));
}

function triangleAngle(array $face, array $vertices): string
{
    [$a, $b, $c] = array_map(fn($v) => $vertices[$v], $face['vertices']);
    $minimum = min(dot(difference($b, $a), difference($c, $a)),
        dot(difference($c, $b), difference($a, $b)), dot(difference($a, $c), difference($b, $c)));
    return $minimum < 0 ? 'obtuse' : ($minimum === 0 ? 'right' : 'acute');
}

function faceGeometry(array $face, array $vertices): array
{
    $n = normal($face, $vertices);
    return ['normal' => $n, 'q' => dot($n, $n), 'determinant' => determinant($face, $vertices),
        'angle' => triangleAngle($face, $vertices)];
}

function meshArea(array $geometry, array $indices): float
{
    $total = 0.0;
    foreach ($indices as $index) $total += sqrt($geometry[$index]['q']);
    return $total / 2;
}

function volume6(array $faces, array $vertices, array $indices): int
{
    $total = 0;
    foreach ($indices as $index) $total += determinant($faces[$index], $vertices);
    return $total;
}

function fraction(int $numerator, int $denominator): string
{
    if ($numerator === 0) return '0';
    if ($denominator < 0) {
        $numerator = -$numerator;
        $denominator = -$denominator;
    }
    $a = abs($numerator);
    $b = $denominator;
    while ($b !== 0) {
        $remainder = $a % $b;
        $a = $b;
        $b = $remainder;
    }
    $numerator = intdiv($numerator, $a);
    $denominator = intdiv($denominator, $a);
    return $denominator === 1 ? (string)$numerator : $numerator . '/' . $denominator;
}

function centroid(array $faces, array $vertices, array $indices, array $geometry, int $volume): array
{
    $totals = [0, 0, 0];
    foreach ($indices as $index) {
        [$a, $b, $c] = array_map(fn($v) => $vertices[$v], $faces[$index]['vertices']);
        for ($k = 0; $k < 3; $k++) $totals[$k] += $geometry[$index]['determinant'] * ($a[$k] + $b[$k] + $c[$k]);
    }
    return array_map(fn($sum) => fraction($sum, 4 * $volume), $totals);
}

function solidAngle(array $face, array $vertices, array $point): float
{
    [$a, $b, $c] = array_map(fn($v) => difference($vertices[$v], $point), $face['vertices']);
    $la = sqrt(dot($a, $a));
    $lb = sqrt(dot($b, $b));
    $lc = sqrt(dot($c, $c));
    $denominator = $la * $lb * $lc + dot($a, $b) * $lc + dot($b, $c) * $la + dot($c, $a) * $lb;
    return 2 * atan2(dot($a, cross($b, $c)), $denominator);
}

function winding(array $faces, array $vertices, array $indices, array $point): int
{
    $total = 0.0;
    foreach ($indices as $index) $total += solidAngle($faces[$index], $vertices, $point);
    return (int)round($total / (4 * M_PI));
}

function realNumber(float $value): string
{
    return number_format($value, 3, '.', '');
}
