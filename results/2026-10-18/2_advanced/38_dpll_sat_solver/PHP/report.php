<?php

function items(string $prefix, array $values): string
{
    $parts = [];
    foreach ($values as $name => $value) $parts[] = $name . '=' . $value;
    return $prefix . ' ' . implode(' ', $parts);
}

function numberList(array $values): string
{
    return $values ? implode(',', $values) : '-';
}

function frequencyList(array $values): string
{
    $counts = [];
    foreach ($values as $value) $counts[$value] = ($counts[$value] ?? 0) + 1;
    ksort($counts, SORT_NUMERIC);
    $parts = [];
    foreach ($counts as $value => $count) $parts[] = $value . ':' . $count;
    return $parts ? implode(',', $parts) : '-';
}

function boardLines(array $columns): array
{
    return array_map(fn($column) => str_repeat('.', $column - 1) . 'Q' . str_repeat('.', count($columns) - $column), $columns);
}

function writeParagraphs(string $filename, array $paragraphs): void
{
    $blocks = array_map(fn($lines) => implode("\n", $lines), $paragraphs);
    file_put_contents('output/' . $filename, $blocks ? implode("\n\n", $blocks) . "\n" : '');
}

function writeCsv(string $filename, array $rows): void
{
    file_put_contents('output/' . $filename, implode("\n", array_map(fn($row) => implode(',', $row), $rows)) . "\n");
}
