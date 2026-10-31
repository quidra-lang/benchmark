<?php

function real(?float $value, int $digits = 4): string
{
    if ($value === null) {
        return '-';
    }
    $text = number_format(abs($value), $digits, '.', '');
    return $value < 0 && (float) $text !== 0.0 ? '-' . $text : $text;
}

function ratio(int $numerator, int $denominator): string
{
    if ($denominator === 0) {
        return '-';
    }
    $rounded = intdiv(20000 * $numerator + $denominator, 2 * $denominator);
    return intdiv($rounded, 10000) . '.' . str_pad((string) ($rounded % 10000), 4, '0', STR_PAD_LEFT);
}

function prediction(array $scores): int
{
    $best = 0;
    for ($k = 1; $k < count($scores); $k++) {
        if ($scores[$k] > $scores[$best]) {
            $best = $k;
        }
    }
    return $best;
}

function secondClass(array $scores, int $first): int
{
    $best = $first === 0 ? 1 : 0;
    for ($k = 0; $k < count($scores); $k++) {
        if ($k !== $first && $scores[$k] > $scores[$best]) {
            $best = $k;
        }
    }
    return $best;
}

function confusion(array $images, array $results, int $classes): array
{
    $matrix = array_fill(0, $classes, array_fill(0, $classes, 0));
    foreach ($images as $i => $image) {
        $matrix[$image->label][$results[$i]->predicted]++;
    }
    return $matrix;
}

function perClass(array $matrix): array
{
    $values = [];
    for ($k = 0; $k < count($matrix); $k++) {
        $support = 0;
        $predicted = 0;
        for ($i = 0; $i < count($matrix); $i++) {
            $support += $matrix[$k][$i];
            $predicted += $matrix[$i][$k];
        }
        $values[] = (object) ['support' => $support, 'predicted' => $predicted, 'precision' => ratio($matrix[$k][$k], $predicted),
            'recall' => ratio($matrix[$k][$k], $support), 'f1' => ratio(2 * $matrix[$k][$k], $support + $predicted)];
    }
    return $values;
}

function levelMaps(array $maps, int $width, int $height): array
{
    $rows = [];
    for ($row = 0; $row < $height; $row++) {
        $parts = [];
        foreach ($maps as $map) {
            $parts[] = implode('', array_slice($map, $row * $width, $width));
        }
        $rows[] = implode(' ', $parts);
    }
    return $rows;
}

function imageRows(object $image, int $width, int $height): array
{
    $pixels = strtr($image->pixels, '01', '.#');
    $rows = [];
    for ($row = 0; $row < $height; $row++) {
        $rows[] = substr($pixels, $row * $width, $width);
    }
    return $rows;
}
