<?php

function fixed_width_line(string $label, array $cells, int $labelWidth, int $cellWidth): string
{
    $line = str_pad($label, $labelWidth);
    foreach ($cells as $cell) {
        $line .= str_pad((string) $cell, $cellWidth, ' ', STR_PAD_LEFT);
    }
    return $line;
}

function rounded_percent(int $part, int $whole): int
{
    return intdiv(200 * $part + $whole, 2 * $whole);
}

function write_files(string $directory, array $files): void
{
    if (!is_dir($directory)) {
        mkdir($directory, 0777, true);
    }
    foreach ($files as $name => $lines) {
        file_put_contents($directory . '/' . $name, implode("\n", $lines) . "\n");
    }
}
