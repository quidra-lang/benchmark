<?php

function vecAdd(array $a, array $b): array
{
    return [$a[0] + $b[0], $a[1] + $b[1], $a[2] + $b[2]];
}

function vecSub(array $a, array $b): array
{
    return [$a[0] - $b[0], $a[1] - $b[1], $a[2] - $b[2]];
}

function vecNeg(array $a): array
{
    return [-$a[0], -$a[1], -$a[2]];
}

function vecDot(array $a, array $b): int
{
    return floorDiv($a[0] * $b[0] + $a[1] * $b[1] + $a[2] * $b[2], S);
}

function vecScale(array $a, int $k): array
{
    return [floorDiv($a[0] * $k, S), floorDiv($a[1] * $k, S), floorDiv($a[2] * $k, S)];
}

function vecLength(array $a): int
{
    return integerSqrt($a[0] * $a[0] + $a[1] * $a[1] + $a[2] * $a[2]);
}

function vecNormalize(array $a): array
{
    $length = vecLength($a);
    return [floorDiv($a[0] * S, $length), floorDiv($a[1] * S, $length), floorDiv($a[2] * S, $length)];
}
