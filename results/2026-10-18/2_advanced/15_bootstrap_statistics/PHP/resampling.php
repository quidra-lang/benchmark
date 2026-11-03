<?php

namespace Bootstrap;

function float_sum(array $values): float
{
    $total = 0.0;
    foreach ($values as $value) {
        $total += $value;
    }
    return $total;
}

function sorted(array $values): array
{
    sort($values, SORT_NUMERIC);
    return $values;
}

function mean(array $values): float
{
    return array_sum($values) / (100 * count($values));
}

function doubled_median(array $values): int
{
    $ordered = sorted($values);
    $count = count($ordered);
    return $ordered[intdiv($count + 1, 2) - 1] + $ordered[intdiv($count + 2, 2) - 1];
}

function median(array $values): float
{
    return doubled_median($values) / 200;
}

function trimmed_mean(array $values): float
{
    $trim = intdiv(count($values), 10);
    return array_sum(array_slice(sorted($values), $trim, count($values) - 2 * $trim)) / (100 * (count($values) - 2 * $trim));
}

function moments(array $values): array
{
    $center = mean($values);
    $second = 0.0;
    $third = 0.0;
    $fourth = 0.0;
    foreach ($values as $value) {
        $e = $value / 100 - $center;
        $second += $e * $e;
        $third += $e * $e * $e;
        $fourth += $e * $e * $e * $e;
    }
    $count = count($values);
    return ['sd' => sqrt($second / ($count - 1)), 'm2' => $second / $count, 'm3' => $third / $count, 'm4' => $fourth / $count];
}

function sd(array $values): float
{
    return moments($values)['sd'];
}

function mad(array $values): float
{
    $center = doubled_median($values);
    return doubled_median(array_map(fn($value) => abs(2 * $value - $center), $values)) / 400;
}

function quantile_numerator(array $values, int $percent): int
{
    $ordered = sorted($values);
    $position = (count($values) - 1) * $percent;
    $index = intdiv($position, 100);
    $fraction = $position % 100;
    return 100 * $ordered[$index] + ($fraction === 0 ? 0 : $fraction * ($ordered[$index + 1] - $ordered[$index]));
}

function winsorized(array $values): array
{
    $ordered = sorted($values);
    $trim = intdiv(count($values), 10);
    $low = $ordered[$trim];
    $high = $ordered[count($values) - $trim - 1];
    return array_map(fn($value) => min(max($value, $low), $high), $values);
}

function mean_difference(array $x, array $y): float
{
    return (count($y) * array_sum($x) - count($x) * array_sum($y)) / (100 * count($x) * count($y));
}

function median_ratio(array $x, array $y): float
{
    return doubled_median($x) / doubled_median($y);
}

function hodges_lehmann(array $x, array $y): float
{
    $differences = [];
    foreach ($x as $first) {
        foreach ($y as $second) {
            $differences[] = $first - $second;
        }
    }
    return doubled_median($differences) / 200;
}

function pooled_sd(array $x, array $y): float
{
    $sx = sd($x);
    $sy = sd($y);
    return sqrt(((count($x) - 1) * $sx * $sx + (count($y) - 1) * $sy * $sy) / (count($x) + count($y) - 2));
}

function cohen_d(array $x, array $y): float
{
    return mean_difference($x, $y) / pooled_sd($x, $y);
}

function correlation(array $x, array $y): float
{
    $mx = mean($x);
    $my = mean($y);
    $products = 0.0;
    $first = 0.0;
    $second = 0.0;
    foreach ($x as $index => $value) {
        $e = $value / 100 - $mx;
        $f = $y[$index] / 100 - $my;
        $products += $e * $f;
        $first += $e * $e;
        $second += $f * $f;
    }
    return $products / sqrt($first * $second);
}

function sample_statistics(array $values): array
{
    return [mean($values), median($values), trimmed_mean($values), sd($values)];
}

function pair_statistics(array $x, array $y): array
{
    return [mean_difference($x, $y), median_ratio($x, $y), hodges_lehmann($x, $y), cohen_d($x, $y)];
}

function resample_indices(Minstd $generator, int $size): array
{
    $indices = [];
    for ($index = 0; $index < $size; $index++) {
        $indices[] = $generator->below($size);
    }
    return $indices;
}

function ordinary_indices(Minstd $generator, int $size, int $count): array
{
    $result = [];
    for ($replicate = 0; $replicate < $count; $replicate++) {
        $result[] = resample_indices($generator, $size);
    }
    return $result;
}

function balanced_indices(Minstd $generator, int $size, int $count): array
{
    $sequence = [];
    for ($replicate = 0; $replicate < $count; $replicate++) {
        array_push($sequence, ...range(0, $size - 1));
    }
    return array_chunk($generator->shuffle($sequence), $size);
}

function without(array $values, int $index): array
{
    array_splice($values, $index, 1);
    return $values;
}

function mean_and_se(array $values): array
{
    $average = float_sum($values) / count($values);
    $squares = 0.0;
    foreach ($values as $value) {
        $e = $value - $average;
        $squares += $e * $e;
    }
    return [$average, sqrt($squares / (count($values) - 1))];
}

function phi(float $x): float
{
    if ($x < 0) {
        return 1 - phi(-$x);
    }
    $eta = 1 / (1 + 0.2316419 * $x);
    $psi = $eta * (0.319381530 + $eta * (-0.356563782 + $eta * (1.781477937 + $eta * (-1.821255978 + $eta * 1.330274429))));
    return 1 - 0.3989422804014327 * exp(-($x * $x) / 2) * $psi;
}

function phi_inverse(float $p): float
{
    if ($p > 0.5) {
        return -phi_inverse(1 - $p);
    }
    $eta = sqrt(-2 * log($p));
    return -($eta - (2.515517 + $eta * (0.802853 + $eta * 0.010328)) / (1 + $eta * (1.432788 + $eta * (0.189269 + $eta * 0.001308))));
}
