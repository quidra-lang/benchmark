<?php

function hex2(int $value): string
{
    return strtoupper(str_pad(dechex($value), 2, '0', STR_PAD_LEFT));
}

function hex1(int $value): string
{
    return strtoupper(dechex($value));
}

function isqrt(int $value): int
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

function adler32(array $samples): string
{
    $a = 1;
    $b = 0;
    foreach ($samples as $value) {
        $a = ($a + $value) % 65521;
        $b = ($b + $a) % 65521;
    }
    return strtoupper(str_pad(dechex($b * 65536 + $a), 8, '0', STR_PAD_LEFT));
}

function statistics(array $values, int $center = 128): object
{
    $peak = 0;
    $minimum = $maximum = $values[0];
    $squares = $crossings = 0;
    foreach ($values as $i => $value) {
        $difference = $value - $center;
        $peak = max($peak, abs($difference));
        $minimum = min($minimum, $value);
        $maximum = max($maximum, $value);
        $squares += $difference * $difference;
        if ($i > 0 && ($values[$i - 1] < $center) !== ($value < $center)) {
            $crossings++;
        }
    }
    return (object) ['peak' => $peak, 'minimum' => $minimum, 'maximum' => $maximum,
        'rms' => isqrt(intdiv($squares, count($values))), 'crossings' => $crossings];
}

function hexDump(array $samples): array
{
    $lines = [];
    for ($i = 0; $i < count($samples); $i += 32) {
        $lines[] = implode('', array_map('hex2', array_slice($samples, $i, 32)));
    }
    return $lines;
}
