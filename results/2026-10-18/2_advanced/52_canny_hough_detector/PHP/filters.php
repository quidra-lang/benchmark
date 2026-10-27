<?php

function clamped(array $values, int $x, int $y, int $width, int $height): int
{
    $x = min(max($x, 0), $width - 1);
    $y = min(max($y, 0), $height - 1);
    return $values[$y * $width + $x];
}

function smooth(array $image, array $params): array
{
    $width = $image['width'];
    $height = $image['height'];
    $size = $params['gauss_size'];
    $half = intdiv($size - 1, 2);
    $result = array_fill(0, $width * $height, 0);
    for ($y = 0; $y < $height; $y++) {
        for ($x = 0; $x < $width; $x++) {
            $sum = 0;
            for ($j = 0; $j < $size; $j++) {
                for ($i = 0; $i < $size; $i++) {
                    $sum += $params['gauss_kernel'][$j * $size + $i] * clamped($image['pixels'], $x + $i - $half, $y + $j - $half, $width, $height);
                }
            }
            $result[$y * $width + $x] = intdiv($sum, $params['gauss_divisor']);
        }
    }
    return $result;
}

function gradient(array $values, int $width, int $height): array
{
    $gx = $gy = $magnitude = array_fill(0, $width * $height, 0);
    for ($y = 0; $y < $height; $y++) {
        for ($x = 0; $x < $width; $x++) {
            $q = [];
            for ($dy = -1; $dy <= 1; $dy++) for ($dx = -1; $dx <= 1; $dx++) $q[] = clamped($values, $x + $dx, $y + $dy, $width, $height);
            $index = $y * $width + $x;
            $gx[$index] = ($q[2] + 2 * $q[5] + $q[8]) - ($q[0] + 2 * $q[3] + $q[6]);
            $gy[$index] = ($q[6] + 2 * $q[7] + $q[8]) - ($q[0] + 2 * $q[1] + $q[2]);
            $magnitude[$index] = abs($gx[$index]) + abs($gy[$index]);
        }
    }
    return compact('gx', 'gy', 'magnitude');
}
