<?php

function real($value, $digits) {
    if ($value === null) return 'none';
    $text = sprintf('%.' . $digits . 'F', abs($value));
    return $value < 0 && (float)$text != 0.0 ? '-' . $text : $text;
}

function plotLines($cells, $heights) {
    $labels = [];
    $width = 0;
    foreach ($heights as $height) {
        $label = real($height / 100, 2);
        $labels[] = $label;
        $width = max($width, strlen($label));
    }
    $result = [];
    foreach ($cells as $i => $row) $result[] = str_pad($labels[$i], $width, ' ', STR_PAD_LEFT) . ' |' . implode('', $row) . '|';
    $axis = str_repeat(' ', $width) . ' +';
    for ($column = 0; $column < count($cells[0]); $column++) $axis .= $column % 6 === 0 ? '+' : '-';
    $result[] = $axis . '+';
    return $result;
}

function writeFiles($files) {
    foreach ($files as $name => $lines) file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}
