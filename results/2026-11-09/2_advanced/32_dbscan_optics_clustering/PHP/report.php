<?php

function fraction(int $numerator, int $denominator): string
{
    $a = abs($numerator);
    $b = $denominator;
    while ($b !== 0) {
        [$a, $b] = [$b, $a % $b];
    }
    return intdiv($numerator, $a) . '/' . intdiv($denominator, $a);
}

function root(float|int $value): string
{
    return $value === INF ? '-' : number_format(sqrt($value), 3, '.', '');
}

function formatInteger(float|int $value): string
{
    return $value === INF ? '-' : (string) $value;
}

function ariValue(int $numerator, int $denominator): string
{
    $text = number_format($numerator / $denominator, 4, '.', '');
    return $text === '-0.0000' ? '0.0000' : $text;
}

function frame(array $rows): array
{
    $border = '+' . str_repeat('-', strlen($rows[0])) . '+';
    return array_merge([$border], array_map(fn($row) => '|' . $row . '|', $rows), [$border]);
}

function writeLines(string $name, array $lines): void
{
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}
