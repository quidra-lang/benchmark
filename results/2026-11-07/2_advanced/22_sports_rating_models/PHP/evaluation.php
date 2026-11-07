<?php
declare(strict_types=1);

namespace SportsRatings;

function sigma(float $value): float { return 1 / (1 + exp(-$value)); }

function fitLink(array $features, array $results, int $iterations): array
{
    $alpha = $beta = 0.0;
    for ($iteration = 0; $iteration < $iterations; $iteration++) {
        $g0 = $g1 = $h00 = $h01 = $h11 = 0.0;
        foreach ($features as $index => $z) {
            $p = sigma($alpha + $beta * $z);
            $w = $p * (1 - $p);
            $delta = $results[$index] - $p;
            $g0 += $delta;
            $g1 += $delta * $z;
            $h00 += $w;
            $h01 += $w * $z;
            $h11 += $w * $z * $z;
        }
        $determinant = $h00 * $h11 - $h01 * $h01;
        $alphaChange = ($h11 * $g0 - $h01 * $g1) / $determinant;
        $betaChange = ($h00 * $g1 - $h01 * $g0) / $determinant;
        $alpha += $alphaChange;
        $beta += $betaChange;
    }
    return [$alpha, $beta];
}

function logLoss(float $p, float $y): float
{
    if ($y === 1.0) {
        return -log($p);
    }
    if ($y === 0.0) {
        return -log(1 - $p);
    }
    return -(log($p) / 2 + log(1 - $p) / 2);
}

function brierScore(float $p, float $y): float { return ($p - $y) * ($p - $y); }
function correctness2(float $p, float $y): int
{
    if ($y === 0.5) {
        return 1;
    }
    return $p > 0.5 && $y === 1.0 || $p < 0.5 && $y === 0.0 ? 2 : 0;
}

function averageRanks2(array $values): array
{
    $ranks = [];
    foreach ($values as $value) {
        $greater = $equal = 0;
        foreach ($values as $other) {
            $order = compareValues($other, $value);
            $greater += (int)($order > 0);
            $equal += (int)($order === 0);
        }
        $ranks[] = 2 * $greater + $equal + 1;
    }
    return $ranks;
}

function kendallTau(array $first, array $second): Fraction
{
    $count = count($first);
    $numerator = 0;
    for ($i = 0; $i < $count; $i++) {
        for ($j = $i + 1; $j < $count; $j++) {
            $numerator += compareValues($first[$i], $first[$j]) * compareValues($second[$i], $second[$j]);
        }
    }
    return new Fraction($numerator, intdiv($count * ($count - 1), 2));
}

function spearmanRho(array $first, array $second): Fraction
{
    $a = averageRanks2($first);
    $b = averageRanks2($second);
    $squares = 0;
    $count = count($first);
    for ($index = 0; $index < $count; $index++) {
        $difference = $a[$index] - $b[$index];
        $squares += $difference * $difference;
    }
    $denominator = 4 * $count * ($count * $count - 1);
    return new Fraction($denominator - 6 * $squares, $denominator);
}
