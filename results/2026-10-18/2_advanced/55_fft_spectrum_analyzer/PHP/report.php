<?php

function fixed($value)
{
    $text = number_format(abs($value), 4, '.', '');
    return $value < 0 && $text !== '0.0000' ? '-' . $text : $text;
}

function writeLines($name, $lines)
{
    file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}

function writeCsv($name, $rows)
{
    writeLines($name, array_map(fn($row) => implode(',', $row), $rows));
}

function shadeLines($levels, $sampleRate, $frameLength)
{
    $shades = ' .:-=+*#%@';
    $lines = [];
    for ($k = intdiv($frameLength, 2); $k >= 0; $k--) {
        $characters = '';
        foreach ($levels as $frame) {
            $characters .= $shades[$frame[$k]];
        }
        $lines[] = str_pad(fixed($k * $sampleRate / $frameLength), 9, ' ', STR_PAD_LEFT) . ' |' . $characters . '|';
    }
    return $lines;
}
