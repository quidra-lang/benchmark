<?php

function formatFixed(float $value, int $places): string
{
    $result = number_format($value, $places, '.', '');
    return preg_match('/^-0(?:\\.0+)?$/', $result) ? substr($result, 1) : $result;
}

function formatTime(int $milliseconds): string
{
    return intdiv($milliseconds, 1000) . '.' . str_pad((string) ($milliseconds % 1000), 3, '0', STR_PAD_LEFT);
}

function temperatureRows(object $mesh, array $field): array
{
    $lines = [];
    for ($r = 0; $r < $mesh->height; $r++) {
        $lines[] = implode(' ', array_map(fn($value) => formatFixed($value, 2), array_slice($field, $r * $mesh->width, $mesh->width)));
    }
    return $lines;
}

function isothermRows(object $mesh, array $field, array $bands): object
{
    $hottest = 0;
    for ($p = 1; $p < $mesh->count; $p++) if ($field[$p] > $field[$hottest]) $hottest = $p;
    $counts = array_fill(0, count($bands) + 1, 0);
    $characters = [];
    foreach ($field as $p => $value) {
        $digit = 0;
        foreach ($bands as $boundary) if ($boundary <= $value) $digit++;
        $counts[$digit]++;
        $characters[] = $p === $hottest ? '*' : (string) $digit;
    }
    $lines = [];
    for ($r = 0; $r < $mesh->height; $r++) $lines[] = implode('', array_slice($characters, $r * $mesh->width, $mesh->width));
    return (object) compact('counts', 'lines');
}

function writeFiles(array $files): void
{
    if (!is_dir('output')) mkdir('output', 0777, true);
    foreach ($files as $name => $lines) file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}
