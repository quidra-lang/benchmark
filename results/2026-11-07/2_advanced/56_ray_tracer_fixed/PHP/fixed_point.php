<?php

const S = 4096;

function floorDiv(int $a, int $b): int
{
    $quotient = intdiv($a, $b);
    return $a % $b !== 0 && (($a < 0) !== ($b < 0)) ? $quotient - 1 : $quotient;
}

function mul(int $a, int $b): int
{
    return floorDiv($a * $b, S);
}

function integerSqrt(int $n): int
{
    $low = 0;
    $high = 1;
    while ($high * $high <= $n) {
        $high *= 2;
    }
    while ($high - $low > 1) {
        $middle = intdiv($low + $high, 2);
        if ($middle * $middle <= $n) {
            $low = $middle;
        } else {
            $high = $middle;
        }
    }
    return $low;
}
