<?php

const REGION_ORDER = ['nonocc', 'all', 'disc'];

function truthRegions(array $truth, int $width, int $height): array
{
    $known = $occluded = [];
    foreach ($truth as $p => $g) {
        if ($g === 0) continue;
        $known[] = $p;
        $x = $p % $width;
        $y = intdiv($p, $width);
        $hidden = $x < $g;
        for ($x2 = 0; $x2 < $width && !$hidden; $x2++) {
            $other = $truth[$y * $width + $x2];
            $hidden = $other > $g && $x2 - $other === $x - $g;
        }
        if ($hidden) $occluded[] = $p;
    }
    $hidden = array_fill_keys($occluded, true);
    $nonocc = [];
    $disc = [];
    foreach ($known as $p) {
        if (isset($hidden[$p])) continue;
        $nonocc[] = $p;
        $x = $p % $width;
        $y = intdiv($p, $width);
        $discontinuity = false;
        for ($yy = max(0, $y - 1); $yy <= min($height - 1, $y + 1) && !$discontinuity; $yy++) {
            for ($xx = max(0, $x - 1); $xx <= min($width - 1, $x + 1); $xx++) {
                $value = $truth[$yy * $width + $xx];
                if ($value !== 0 && abs($value - $truth[$p]) >= 2) {
                    $discontinuity = true;
                    break;
                }
            }
        }
        if ($discontinuity) $disc[] = $p;
    }
    return ['all' => $known, 'nonocc' => $nonocc, 'disc' => $disc, 'occluded' => $occluded];
}

function evaluate(array $image, array $truth, array $region): array
{
    $valid = $bad1 = $bad2 = $errorSum = $exact = 0;
    foreach ($region as $p) {
        if ($image[$p] === 0) {
            $bad1++;
            $bad2++;
            continue;
        }
        $valid++;
        $error = abs($image[$p] - $truth[$p]);
        if ($error > 1) $bad1++;
        if ($error > 2) $bad2++;
        $errorSum += $error;
        if ($error === 0) $exact++;
    }
    return ['pixels' => count($region), 'valid' => $valid, 'bad1' => $bad1, 'bad2' => $bad2,
        'errorSum' => $errorSum, 'mae' => $valid ? twoDecimals($errorSum, $valid) : '-', 'exact' => $exact];
}

function gcdValue(int $a, int $b): int
{
    while ($b !== 0) {
        $remainder = $a % $b;
        $a = $b;
        $b = $remainder;
    }
    return $a;
}

function ratio(int $numerator, int $denominator): string
{
    if ($denominator === 0) return '0/1 0.00';
    $divisor = gcdValue($numerator, $denominator);
    return intdiv($numerator, $divisor) . '/' . intdiv($denominator, $divisor) . ' ' . twoDecimals(100 * $numerator, $denominator);
}
