<?php

function roundedUnits(int $p, int $q): int
{
    return intdiv(2 * $p * 10000 + $q, 2 * $q);
}

function decimal(int $p, int $q): string
{
    $units = roundedUnits($p, $q);
    return intdiv($units, 10000) . '.' . str_pad((string)($units % 10000), 4, '0', STR_PAD_LEFT);
}

function percentage(int $p, int $q): string
{
    if ($q === 0) return '-';
    $units = roundedUnits($p, $q);
    return intdiv($units, 100) . '.' . str_pad((string)($units % 100), 2, '0', STR_PAD_LEFT);
}

function fraction(int $p, int $q): string
{
    $a = $p;
    $b = $q;
    while ($b !== 0) {
        $remainder = $a % $b;
        $a = $b;
        $b = $remainder;
    }
    return intdiv($p, $a) . '/' . intdiv($q, $a);
}

function hexText(int $value): string
{
    return str_pad(dechex($value), 8, '0', STR_PAD_LEFT);
}

function cycleHeader(int $start, int $end): string
{
    $digits = '';
    for ($cycle = $start; $cycle <= $end; $cycle++) $digits .= $cycle % 10;
    return 'cycle' . str_repeat(' ', 18) . $digits;
}

function diagramRow(array $row, int $start, int $end): ?array
{
    $characters = array_fill(0, $end - $start + 1, '.');
    foreach ($row['segments'] as $segment) {
        for ($cycle = max($start, $segment['from']); $cycle <= min($end, $segment['to']); $cycle++) {
            $characters[$cycle - $start] = $cycle === $segment['from'] ? $segment['first'] : $segment['rest'];
        }
    }
    if ($row['cancel'] !== null && $row['cancel'] >= $start && $row['cancel'] <= $end) $characters[$row['cancel'] - $start] = 'x';
    if (!array_filter($characters, fn($character) => $character !== '.')) return null;
    $line = str_pad((string)($row['number'] ?? '-'), 6, ' ', STR_PAD_LEFT) . ' ' . hexText($row['pc']) . ' ' .
        str_pad($row['className'], 6) . ' ' . implode('', $characters) . $row['annotation'];
    return ['line' => $line, 'stallCells' => count(array_filter($characters, fn($c) => $c === '*')),
        'flushed' => count(array_filter($characters, fn($c) => $c === 'x'))];
}

function writeReport(string $name, array $lines): void
{
    if (!is_dir('output')) mkdir('output', 0777, true);
    file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}
