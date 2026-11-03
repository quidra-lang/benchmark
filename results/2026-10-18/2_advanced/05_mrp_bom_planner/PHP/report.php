<?php
function money(int $cents): string { return intdiv($cents, 100) . '.' . sprintf('%02d', $cents % 100); }
function percent(int $part, int $whole): int { return intdiv(200 * $part + $whole, 2 * $whole); }
function table_row(string $label, array $values, int $width): string { return str_pad($label, 10) . implode('', array_map(fn($value) => str_pad((string)$value, $width, ' ', STR_PAD_LEFT), $values)); }
function write_report(string $name, array $lines): void { if (!is_dir('output')) mkdir('output', 0777, true); file_put_contents("output/$name", $lines ? implode("\n", $lines) . "\n" : ''); }
