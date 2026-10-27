<?php

function plot_real($value)
{
    $text = sprintf('%.4F', $value);
    return $text === '-0.0000' ? '0.0000' : $text;
}

function plot_fraction($value)
{
    return $value === null ? '-' : $value[0] . '/' . $value[1] . ' ' . plot_real($value[0] / $value[1]);
}

function plot_frame($rows)
{
    $border = '+' . str_repeat('-', count($rows[0])) . '+';
    $lines = [$border];
    foreach ($rows as $row) $lines[] = '|' . implode('', $row) . '|';
    $lines[] = $border;
    return $lines;
}

function plot_cell($value, $low, $high, $size)
{
    return (int) floor(($value - $low) / ($high - $low) * ($size - 1) + 0.5);
}

function plot_write_lines($filename, $lines)
{
    file_put_contents('output/' . $filename, implode("\n", $lines) . "\n");
}
