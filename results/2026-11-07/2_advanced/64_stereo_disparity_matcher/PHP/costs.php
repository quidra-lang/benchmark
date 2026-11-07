<?php

function clamped(array $image, int $width, int $height, int $x, int $y): int
{
    return $image[min(max($y, 0), $height - 1) * $width + min(max($x, 0), $width - 1)];
}

function boxSum(array $image, int $width, int $height, int $window): array
{
    $radius = intdiv($window, 2);
    $paddedWidth = $width + 2 * $radius;
    $paddedHeight = $height + 2 * $radius;
    $integral = array_fill(0, $paddedHeight + 1, array_fill(0, $paddedWidth + 1, 0));
    for ($y = 0; $y < $paddedHeight; $y++) {
        $row = 0;
        for ($x = 0; $x < $paddedWidth; $x++) {
            $row += clamped($image, $width, $height, $x - $radius, $y - $radius);
            $integral[$y + 1][$x + 1] = $integral[$y][$x + 1] + $row;
        }
    }
    $output = [];
    for ($y = 0; $y < $height; $y++) {
        for ($x = 0; $x < $width; $x++) {
            $output[] = $integral[$y + $window][$x + $window] - $integral[$y][$x + $window] -
                $integral[$y + $window][$x] + $integral[$y][$x];
        }
    }
    return $output;
}

function census(array $image, int $width, int $height): array
{
    $output = [];
    for ($y = 0; $y < $height; $y++) {
        for ($x = 0; $x < $width; $x++) {
            $code = 0;
            for ($dy = -2; $dy <= 2; $dy++) {
                for ($dx = -2; $dx <= 2; $dx++) {
                    if ($dx !== 0 || $dy !== 0) {
                        $code = 2 * $code + (clamped($image, $width, $height, $x + $dx, $y + $dy) < $image[$y * $width + $x] ? 1 : 0);
                    }
                }
            }
            $output[] = $code;
        }
    }
    return $output;
}

function texture(array $image, int $width, int $height, int $window): array
{
    $gradient = [];
    for ($y = 0; $y < $height; $y++) {
        for ($x = 0; $x < $width; $x++) {
            $gradient[] = abs(clamped($image, $width, $height, $x + 1, $y) - clamped($image, $width, $height, $x - 1, $y));
        }
    }
    return boxSum($gradient, $width, $height, $window);
}

function popcount(int $value): int
{
    $count = 0;
    while ($value !== 0) {
        $value &= $value - 1;
        $count++;
    }
    return $count;
}

function costVolume(array $left, array $right, array $censusLeft, array $censusRight, int $width, int $height,
    string $kind, int $window, int $minimum, int $maximum): array
{
    $volume = array_fill(0, count($left), []);
    for ($disparity = $minimum; $disparity <= $maximum; $disparity++) {
        $costs = [];
        for ($y = 0; $y < $height; $y++) {
            for ($x = 0; $x < $width; $x++) {
                $p = $y * $width + $x;
                $q = $y * $width + max($x - $disparity, 0);
                $difference = $left[$p] - $right[$q];
                $costs[] = $kind === 'census' ? popcount($censusLeft[$p] ^ $censusRight[$q]) :
                    ($kind === 'sad' ? abs($difference) : $difference * $difference);
            }
        }
        foreach (boxSum($costs, $width, $height, $window) as $p => $value) $volume[$p][] = $value;
    }
    return $volume;
}
