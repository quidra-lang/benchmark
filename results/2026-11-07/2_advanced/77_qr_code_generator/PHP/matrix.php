<?php

function bitLength(int $value): int
{
    $length = 0;
    while ($value > 0) {
        $value >>= 1;
        $length++;
    }
    return $length;
}

function remainder(int $value, int $divisor): int
{
    $degree = bitLength($divisor) - 1;
    for ($bit = bitLength($value) - 1; $bit >= $degree; $bit--) {
        if (($value & (1 << $bit)) !== 0) {
            $value ^= $divisor << ($bit - $degree);
        }
    }
    return $value;
}

function formatInformation(string $level, int $mask): int
{
    $indicators = ['L' => 1, 'M' => 0, 'Q' => 3, 'H' => 2];
    $value = (8 * $indicators[$level] + $mask) * 1024;
    return ($value + remainder($value, 0x537)) ^ 0x5412;
}

function versionInformation(int $version): int
{
    $value = $version * 4096;
    return $value + remainder($value, 0x1f25);
}

function positions(int $size): object
{
    $format = [[], []];
    $version = [[], []];
    for ($i = 0; $i < 15; $i++) {
        $format[0][] = $i <= 5 ? [8, $i] : ($i === 6 ? [8, 7] : ($i === 7 ? [8, 8] : ($i === 8 ? [7, 8] : [14 - $i, 8])));
        $format[1][] = $i <= 7 ? [$size - 1 - $i, 8] : [8, $size - 15 + $i];
    }
    for ($i = 0; $i < 18; $i++) {
        $version[0][] = [$size - 11 + $i % 3, intdiv($i, 3)];
        $version[1][] = [intdiv($i, 3), $size - 11 + $i % 3];
    }
    return (object) ['format' => $format, 'version' => $version];
}

function writeValue(array &$grid, array $locations, int $value): void
{
    foreach ($locations as $i => [$x, $y]) {
        $grid[$y][$x] = ($value >> $i) & 1;
    }
}

function readValue(array $grid, array $locations): int
{
    $value = 0;
    foreach ($locations as $i => [$x, $y]) {
        $value += $grid[$y][$x] * (1 << $i);
    }
    return $value;
}

function createMatrix(int $version, array $centers): object
{
    $size = 17 + 4 * $version;
    $grid = array_fill(0, $size, array_fill(0, $size, 0));
    $areas = array_fill(0, $size, array_fill(0, $size, 'data'));
    $set = function (int $x, int $y, int $value, string $area = 'function') use (&$grid, &$areas): void {
        $grid[$y][$x] = $value;
        $areas[$y][$x] = $area;
    };
    foreach ([[3, 3], [$size - 4, 3], [3, $size - 4]] as [$cx, $cy]) {
        for ($dy = -4; $dy <= 4; $dy++) {
            for ($dx = -4; $dx <= 4; $dx++) {
                $x = $cx + $dx;
                $y = $cy + $dy;
                $distance = max(abs($dx), abs($dy));
                if ($x >= 0 && $x < $size && $y >= 0 && $y < $size) {
                    $set($x, $y, $distance === 2 || $distance === 4 ? 0 : 1);
                }
            }
        }
    }
    for ($i = 8; $i <= $size - 9; $i++) {
        $set(6, $i, $i % 2 === 0 ? 1 : 0);
        $set($i, 6, $i % 2 === 0 ? 1 : 0);
    }
    for ($iy = 0; $iy < count($centers); $iy++) {
        for ($ix = 0; $ix < count($centers); $ix++) {
            if (($ix === 0 && ($iy === 0 || $iy === count($centers) - 1)) || ($iy === 0 && $ix === count($centers) - 1)) {
                continue;
            }
            for ($dy = -2; $dy <= 2; $dy++) {
                for ($dx = -2; $dx <= 2; $dx++) {
                    $set($centers[$ix] + $dx, $centers[$iy] + $dy, max(abs($dx), abs($dy)) === 1 ? 0 : 1);
                }
            }
        }
    }
    $set(8, $size - 8, 1);
    $locations = positions($size);
    foreach ($locations->format as $copy) {
        foreach ($copy as [$x, $y]) {
            $set($x, $y, 0, 'format');
        }
    }
    if ($version >= 7) {
        foreach ($locations->version as $copy) {
            foreach ($copy as [$x, $y]) {
                $set($x, $y, 0, 'version');
            }
            writeValue($grid, $copy, versionInformation($version));
        }
    }
    $order = [];
    for ($right = $size - 1, $pair = 0; $right >= 1; $right -= 2, $pair++) {
        if ($right === 6) {
            $right--;
        }
        for ($row = 0; $row < $size; $row++) {
            $y = $pair % 2 === 0 ? $size - 1 - $row : $row;
            foreach ([$right, $right - 1] as $x) {
                if ($areas[$y][$x] === 'data') {
                    $order[] = [$x, $y];
                }
            }
        }
    }
    return (object) ['size' => $size, 'grid' => $grid, 'areas' => $areas, 'order' => $order,
        'locations' => $locations, 'functionCount' => $size * $size - count($order)];
}
