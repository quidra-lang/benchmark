<?php

function symbolLines(array $grid): array
{
    $lines = [];
    foreach ($grid as $row) {
        $line = '';
        foreach ($row as $value) {
            $line .= $value === 1 ? '#' : '.';
        }
        $lines[] = $line;
    }
    return $lines;
}

function pbm(array $grid, int $quiet, int $scale): string
{
    $width = (count($grid) + 2 * $quiet) * $scale;
    $border = str_repeat('0', $width);
    $margin = str_repeat('0', $quiet * $scale);
    $lines = ['P1', $width . ' ' . $width];
    for ($i = 0; $i < $quiet * $scale; $i++) {
        $lines[] = $border;
    }
    foreach ($grid as $row) {
        $pixels = $margin;
        foreach ($row as $value) {
            $pixels .= str_repeat((string) $value, $scale);
        }
        $pixels .= $margin;
        for ($i = 0; $i < $scale; $i++) {
            $lines[] = $pixels;
        }
    }
    for ($i = 0; $i < $quiet * $scale; $i++) {
        $lines[] = $border;
    }
    return implode("\n", $lines) . "\n";
}
