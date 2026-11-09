<?php

function hundredths(int $value): string
{
    return intdiv($value, 100) . '.' . str_pad((string)($value % 100), 2, '0', STR_PAD_LEFT);
}

function roundedHundredths(int $numerator, int $denominator): int
{
    return intdiv(200 * $numerator + $denominator, 2 * $denominator);
}

function twoDecimals(int $numerator, int $denominator = 1): string
{
    return hundredths(roundedHundredths($numerator, $denominator));
}

function depthHundredths(int $disparity, int $focal, int $baseline): int
{
    return roundedHundredths($focal * $baseline, $disparity);
}

function subpixel(int $disparity, array $costs, int $minimum, int $maximum, int $focal, int $baseline): array
{
    $d = $disparity - $minimum;
    $a = 0;
    $b = 1;
    if ($disparity > $minimum && $disparity < $maximum && $costs[$d - 1] > $costs[$d] && $costs[$d + 1] >= $costs[$d]) {
        $a = $costs[$d - 1] - $costs[$d + 1];
        $b = 2 * ($costs[$d - 1] - 2 * $costs[$d] + $costs[$d + 1]);
    }
    $q = roundedHundredths($disparity * $b + $a, $b);
    return [hundredths($q), twoDecimals(100 * $focal * $baseline, $q)];
}
