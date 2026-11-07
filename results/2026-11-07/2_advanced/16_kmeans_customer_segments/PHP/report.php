<?php
namespace Segments;

function real_text(float $value): string
{
    $text = number_format($value, 4, '.', '');
    return $text === '-0.0000' ? '0.0000' : $text;
}

function reals(array $values): string
{
    return implode(' ', array_map(__NAMESPACE__.'\\real_text', $values));
}

function rounded_key(float $value): float
{
    return (float)real_text($value);
}

function amount(int $cents): string
{
    $absolute = abs($cents);
    return ($cents < 0 ? '-' : '').intdiv($absolute, 100).'.'.str_pad((string)($absolute % 100), 2, '0', STR_PAD_LEFT);
}

function write_lines(string $name, array $lines): void
{
    file_put_contents('output/'.$name, implode("\n", $lines)."\n");
}
