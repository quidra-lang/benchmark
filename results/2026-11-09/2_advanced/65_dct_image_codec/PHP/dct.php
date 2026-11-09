<?php

function zigzag(): array
{
    $result = [];
    for ($diagonal = 0; $diagonal <= 14; $diagonal++) {
        $positions = [];
        for ($u = 0; $u < 8; $u++) if ($diagonal - $u >= 0 && $diagonal - $u < 8) $positions[] = $u * 8 + $diagonal - $u;
        if ($diagonal % 2 === 0) $positions = array_reverse($positions);
        foreach ($positions as $position) $result[] = $position;
    }
    return $result;
}

function rnd(int $value, int $shift): int { return floorDiv($value + (1 << ($shift - 1)), 1 << $shift); }

function forward(array $values, array $C): array
{
    $intermediate = $result = array_fill(0, 64, 0);
    for ($u = 0; $u < 8; $u++) for ($x = 0; $x < 8; $x++) {
        $sum = 0;
        for ($y = 0; $y < 8; $y++) $sum += $C[$u * 8 + $y] * ($values[$y * 8 + $x] - 128);
        $intermediate[$u * 8 + $x] = rnd($sum, 11);
    }
    for ($u = 0; $u < 8; $u++) for ($v = 0; $v < 8; $v++) {
        $sum = 0;
        for ($x = 0; $x < 8; $x++) $sum += $intermediate[$u * 8 + $x] * $C[$v * 8 + $x];
        $result[$u * 8 + $v] = rnd($sum, 15);
    }
    return $result;
}

function inverse(array $values, array $C): array
{
    $intermediate = $result = array_fill(0, 64, 0);
    for ($y = 0; $y < 8; $y++) for ($v = 0; $v < 8; $v++) {
        $sum = 0;
        for ($u = 0; $u < 8; $u++) $sum += $C[$u * 8 + $y] * $values[$u * 8 + $v];
        $intermediate[$y * 8 + $v] = rnd($sum, 11);
    }
    for ($y = 0; $y < 8; $y++) for ($x = 0; $x < 8; $x++) {
        $sum = 0;
        for ($v = 0; $v < 8; $v++) $sum += $intermediate[$y * 8 + $v] * $C[$v * 8 + $x];
        $result[$y * 8 + $x] = clamp(rnd($sum, 15) + 128);
    }
    return $result;
}

function quantizationTables(array $base, int $quality): array
{
    $scale = $quality < 50 ? intdiv(5000, $quality) : 200 - 2 * $quality;
    return array_map(fn($table) => array_map(fn($value) => min(max(intdiv($value * $scale + 50, 100), 1), 255), $table), $base);
}

function quantize(array $values, array $table): array
{
    $result = [];
    foreach (zigzag() as $index) {
        $magnitude = intdiv(abs($values[$index]) + intdiv($table[$index], 2), $table[$index]);
        $result[] = $values[$index] < 0 ? -$magnitude : $magnitude;
    }
    return $result;
}

function dequantize(array $coefficients, array $table, int $keep = 64): array
{
    $result = array_fill(0, 64, 0);
    $order = zigzag();
    for ($i = 0; $i < $keep; $i++) $result[$order[$i]] = $coefficients[$i] * $table[$order[$i]];
    return $result;
}
