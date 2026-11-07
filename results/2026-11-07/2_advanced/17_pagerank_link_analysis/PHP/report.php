<?php
namespace LinkAnalysis;

function fixed(float $value, int $places = 6): string
{
    $text = number_format($value, $places, '.', '');
    return str_starts_with($text, '-') && (float)$text == 0 ? substr($text, 1) : $text;
}

function scaled(float $value, int $places = 6): int
{
    return (int)round($value * 10 ** $places);
}

function fraction(int $numerator, int $denominator): string
{
    $a = abs($numerator);
    $b = $denominator;
    while ($b !== 0) [$a, $b] = [$b, $a % $b];
    $numerator = intdiv($numerator, $a);
    $denominator = intdiv($denominator, $a);
    return "$numerator/$denominator ".fixed($numerator / $denominator, 4);
}

function write_lines(string $name, array $lines): void
{
    file_put_contents('output/'.$name, implode("\n", $lines)."\n");
}
