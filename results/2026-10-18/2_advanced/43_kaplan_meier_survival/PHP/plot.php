<?php

function plotLines($collections, $width, $height, $time)
{
    $cells = array_fill(0, $height, array_fill(0, $width, ' '));
    $occupy = function ($band, $column, $letter) use (&$cells) {
        $previous = $cells[$band][$column];
        $cells[$band][$column] = $previous === ' ' || $previous === $letter ? $letter : '*';
    };
    foreach ($collections as $g => $collection) {
        $letter = chr(65 + $g);
        $previousBand = null;
        for ($column = 0; $column < $width; $column++) {
            $sampleTime = $column * intdiv($time, $width);
            if ($sampleTime > $collection['maxTime']) {
                break;
            }
            $band = min($height - 1, (int)floor(rowAt($collection['km'], $sampleTime)['survival'] * $height));
            $occupy($band, $column, $letter);
            if ($previousBand !== null && $previousBand - 1 > $band) {
                for ($q = $band + 1; $q < $previousBand; $q++) {
                    $occupy($q, $column, $letter);
                }
            }
            $previousBand = $band;
        }
    }
    $border = '   +' . str_repeat('-', $width) . '+';
    $lines = [$border];
    for ($q = $height - 1; $q >= 0; $q--) {
        $lines[] = str_pad((string)intdiv(100 * $q, $height), 3, ' ', STR_PAD_LEFT) . '|' . implode('', $cells[$q]) . '|';
    }
    $lines[] = $border;
    $lines[] = 'time 0 to ' . $time . ' days, ' . intdiv($time, $width) . ' days per column';
    return $lines;
}
