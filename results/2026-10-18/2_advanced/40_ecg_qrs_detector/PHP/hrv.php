<?php

function integerSqrt(int $value): int
{
    $low = 0;
    $high = 1;
    while ($high * $high <= $value) {
        $high *= 2;
    }
    while ($low + 1 < $high) {
        $middle = intdiv($low + $high, 2);
        if ($middle * $middle <= $value) {
            $low = $middle;
        } else {
            $high = $middle;
        }
    }
    return $low;
}

function root(int $numerator, int $denominator): int
{
    return intdiv(integerSqrt(intdiv(40000 * $numerator, $denominator)) + 1, 2);
}

function meanHeartRate(array $intervals): ?int
{
    return count($intervals) ? rdiv(6000000 * count($intervals), array_sum($intervals)) : null;
}

function sumSquares(array $values): int
{
    $sum = 0;
    foreach ($values as $value) {
        $sum += $value * $value;
    }
    return $sum;
}

function intervalStatistics(array $rr, array $nn, array $pairs): array
{
    $e = count($nn);
    $count = count($pairs);
    $differences = [];
    $sums = [];
    foreach ($pairs as [$a, $b]) {
        $differences[] = $b - $a;
        $sums[] = $a + $b;
    }
    $nnSum = array_sum($nn);
    $differenceSum = array_sum($differences);
    $pairSum = array_sum($sums);
    $nnNumerator = $e * sumSquares($nn) - $nnSum * $nnSum;
    $differenceNumerator = $count * sumSquares($differences) - $differenceSum * $differenceSum;
    $sumNumerator = $count * sumSquares($sums) - $pairSum * $pairSum;
    $nn50 = count(array_filter($differences, fn($value) => abs($value) > 50));
    return [
        'meanRR' => count($rr) ? rdiv(100 * array_sum($rr), count($rr)) : null,
        'meanHR' => meanHeartRate($rr),
        'meanNN' => $e ? rdiv(100 * $nnSum, $e) : null,
        'sdnn' => $e >= 2 ? root($nnNumerator, $e * ($e - 1)) : null,
        'rmssd' => $count ? root(sumSquares($differences), $count) : null,
        'sdsd' => $count >= 2 ? root($differenceNumerator, $count * ($count - 1)) : null,
        'nn50' => $nn50,
        'pnn50' => $count ? rdiv(10000 * $nn50, $count) : null,
        'sd1' => $count >= 2 ? root($differenceNumerator, 2 * $count * ($count - 1)) : null,
        'sd2' => $count >= 2 ? root($sumNumerator, 2 * $count * ($count - 1)) : null,
    ];
}

function histogram(array $intervals): array
{
    $bins = [];
    foreach ($intervals as $interval) {
        $bin = intdiv(16 * $interval, 125);
        $bins[$bin] = ($bins[$bin] ?? 0) + 1;
    }
    ksort($bins, SORT_NUMERIC);
    return $bins;
}

function ranges(array $values, callable $predicate): array
{
    $result = [];
    $start = null;
    for ($i = 0; $i <= count($values); $i++) {
        if ($i < count($values) && $predicate($values[$i])) {
            if ($start === null) {
                $start = $i;
            }
        } elseif ($start !== null) {
            $result[] = [$start, $i - 1];
            $start = null;
        }
    }
    return $result;
}
