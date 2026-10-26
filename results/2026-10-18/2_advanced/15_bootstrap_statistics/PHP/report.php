<?php

namespace Bootstrap;

function real(float $value): string
{
    $text = number_format($value, 4, '.', '');
    return $text === '-0.0000' ? '0.0000' : $text;
}

function p_value(int $a, int $b): string
{
    [$a, $b] = reduced_fraction($a, $b);
    return "$a/$b " . real($a / $b);
}

function number_list(array $numbers): string
{
    sort($numbers, SORT_NUMERIC);
    return $numbers ? implode(' ', $numbers) : 'none';
}

function bin_number(float $value, float $low, float $high, int $bins): int
{
    return min((int) floor($bins * ($value - $low) / ($high - $low)), $bins - 1) + 1;
}

function bar(int $count, int $top): string
{
    return str_repeat('#', intdiv(40 * $count + $top - 1, $top));
}

function write_files(array $files): void
{
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    foreach ($files as $name => $lines) {
        file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
    }
}
