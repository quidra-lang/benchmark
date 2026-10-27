<?php

function formatReal($value, int $digits = 4): string
{
    if ($value === null) {
        return '-';
    }
    $text = sprintf('%.' . $digits . 'F', $value);
    return $text[0] === '-' && (float) $text == 0.0 ? substr($text, 1) : $text;
}

function curvePlot(array $observed, array $fitted): array
{
    $count = count($observed);
    $maximum = max($observed);
    $width = strlen((string) $maximum);
    $canvas = array_fill(0, 20, array_fill(0, 70, '.'));
    for ($x = 0; $x < 70; $x++) {
        $day = intdiv($x * ($count - 1), 69);
        $observedRow = min(19, intdiv(20 * $observed[$day], $maximum));
        $fittedRow = min(19, (int) floor(20 * $fitted[$day] / $maximum));
        $canvas[$observedRow][$x] = $observedRow === $fittedRow ? '#' : 'o';
        if ($fittedRow !== $observedRow) {
            $canvas[$fittedRow][$x] = '*';
        }
    }
    $lines = ['plot observed o fitted * both # days 1 ' . $count . ' max ' . $maximum];
    for ($y = 19; $y >= 0; $y--) {
        $label = str_pad((string) intdiv($maximum * $y, 20), $width, ' ', STR_PAD_LEFT);
        $lines[] = $label . ' |' . implode('', $canvas[$y]);
    }
    $ticks = '';
    for ($x = 0; $x < 70; $x++) {
        $ticks .= $x % 10 === 0 ? '+' : '-';
    }
    $lines[] = str_repeat(' ', $width + 1) . '+' . $ticks;
    $labels = str_repeat(' ', 70);
    for ($x = 0; $x <= 60; $x += 10) {
        $label = (string) (intdiv($x * ($count - 1), 69) + 1);
        for ($i = 0; $i < strlen($label); $i++) {
            $labels[$x + $i] = $label[$i];
        }
    }
    $lines[] = rtrim(str_repeat(' ', $width + 2) . $labels);
    return $lines;
}
