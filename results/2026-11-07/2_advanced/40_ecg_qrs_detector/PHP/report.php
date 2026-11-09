<?php

function floorDiv(int $a, int $b): int
{
    $quotient = intdiv($a, $b);
    return $a < 0 && $a % $b !== 0 ? $quotient - 1 : $quotient;
}

function rdiv(int $a, int $b): int
{
    return floorDiv(2 * $a + $b, 2 * $b);
}

function decimal2(int $value): string
{
    $absolute = abs($value);
    return ($value < 0 ? '-' : '') . intdiv($absolute, 100) . '.' . str_pad((string) ($absolute % 100), 2, '0', STR_PAD_LEFT);
}

function decimal4(int $value): string
{
    return intdiv($value, 10000) . '.' . str_pad((string) ($value % 10000), 4, '0', STR_PAD_LEFT);
}

function fraction(int $numerator, int $denominator): string
{
    $a = $numerator;
    $b = $denominator;
    while ($b !== 0) {
        [$a, $b] = [$b, $a % $b];
    }
    return intdiv($numerator, $a) . '/' . intdiv($denominator, $a);
}

function ratio(int $numerator, int $denominator): string
{
    $raw = $numerator . '/' . $denominator;
    return $denominator > 0 ? $raw . ' reduced=' . fraction($numerator, $denominator) . ' percent=' . decimal2(rdiv(10000 * $numerator, $denominator)) : $raw . ' none';
}

function missing($value): string
{
    return $value === null ? '-' : (string) $value;
}
