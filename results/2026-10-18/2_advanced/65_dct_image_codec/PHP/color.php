<?php

function floorDiv(int $a, int $b): int
{
    $q = intdiv($a, $b);
    return $a < 0 && $a % $b !== 0 ? $q - 1 : $q;
}

function clamp(int $value): int { return min(max($value, 0), 255); }

function toYCbCr(array $pixel): array
{
    [$R, $G, $B] = $pixel;
    return [floorDiv(19595 * $R + 38470 * $G + 7471 * $B + 32768, 65536),
        floorDiv(-11059 * $R - 21709 * $G + 32768 * $B + 8421375, 65536),
        floorDiv(32768 * $R - 27439 * $G - 5329 * $B + 8421375, 65536)];
}

function toRGB(array $pixel): array
{
    [$Y, $Cb, $Cr] = $pixel;
    return [clamp($Y + floorDiv(91881 * ($Cr - 128) + 32768, 65536)),
        clamp($Y + floorDiv(-22554 * ($Cb - 128) - 46802 * ($Cr - 128) + 32768, 65536)),
        clamp($Y + floorDiv(116130 * ($Cb - 128) + 32768, 65536))];
}

function planes(object $image): array
{
    $planes = [[], [], []];
    foreach ($image->pixels as $row) {
        $rows = [[], [], []];
        foreach ($row as $pixel) foreach (toYCbCr($pixel) as $k => $value) $rows[$k][] = $value;
        for ($k = 0; $k < 3; $k++) $planes[$k][] = $rows[$k];
    }
    return $planes;
}

function componentPlanes(object $image, object $geometry): array
{
    $original = planes($image);
    $result = [];
    foreach ($geometry->components as $k => $component) {
        $fx = intdiv($geometry->hMax, $component->h);
        $fy = intdiv($geometry->vMax, $component->v);
        $width = 8 * $component->h * $geometry->mx;
        $height = 8 * $component->v * $geometry->my;
        $plane = [];
        for ($y = 0; $y < $height; $y++) {
            $row = [];
            for ($x = 0; $x < $width; $x++) {
                $sum = 0;
                for ($j = 0; $j < $fy; $j++) for ($i = 0; $i < $fx; $i++) {
                    $sum += $original[$k][min($fy * $y + $j, $image->height - 1)][min($fx * $x + $i, $image->width - 1)];
                }
                $row[] = intdiv($sum, $fx * $fy);
            }
            $plane[] = $row;
        }
        $result[] = $plane;
    }
    return $result;
}

function upsample(array $components, object $geometry): object
{
    $decodedPlanes = [[], [], []];
    $pixels = [];
    for ($y = 0; $y < $geometry->height; $y++) {
        $rows = [[], [], []];
        $pixelRow = [];
        for ($x = 0; $x < $geometry->width; $x++) {
            $values = [];
            foreach ($geometry->components as $k => $component) {
                $value = $components[$k][intdiv($y * $component->v, $geometry->vMax)][intdiv($x * $component->h, $geometry->hMax)];
                $rows[$k][] = $value;
                $values[] = $value;
            }
            $pixelRow[] = toRGB($values);
        }
        for ($k = 0; $k < 3; $k++) $decodedPlanes[$k][] = $rows[$k];
        $pixels[] = $pixelRow;
    }
    return (object) ['planes' => $decodedPlanes, 'image' => (object) ['width' => $geometry->width, 'height' => $geometry->height, 'pixels' => $pixels]];
}
