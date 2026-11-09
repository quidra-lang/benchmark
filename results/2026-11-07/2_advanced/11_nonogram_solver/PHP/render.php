<?php
function stateChar(int $state): string { return ['?', '#', '.'][$state]; }
function charState(string $char): int { return match ($char) { '?' => CELL_UNKNOWN, '#' => CELL_FILLED, '.' => CELL_EMPTY }; }
function stateString(array $cells): string { return implode('', array_map('stateChar', $cells)); }
function gridDisplay(array $names, array $grids): array { $lines = ['grid ' . implode(' ', $names)]; foreach ($grids[0] as $r => $row) $lines[] = implode(' | ', array_map(fn($grid) => stateString($grid[$r]), $grids)); return $lines; }
function answerSheet(array $rows, array $columns, array $grid): array {
    $tokens = array_map(fn($clue) => explode(' ', spaced($clue)), $columns); $width = 0; $depth = 0; $margin = 0;
    foreach ($tokens as $column) { $depth = max($depth, count($column)); foreach ($column as $token) $width = max($width, strlen($token) + 1); } foreach ($rows as $clue) $margin = max($margin, strlen(spaced($clue))); $lines = [];
    for ($line = 0; $line < $depth; $line++) { $text = str_repeat(' ', $margin); foreach ($tokens as $column) { $skip = $depth - count($column); $text .= $line >= $skip ? str_pad($column[$line - $skip], $width, ' ', STR_PAD_LEFT) : str_repeat(' ', $width); } $lines[] = rtrim($text, ' '); }
    foreach ($rows as $r => $clue) { $text = str_pad(spaced($clue), $margin, ' ', STR_PAD_LEFT); foreach ($grid[$r] as $state) $text .= str_repeat(' ', $width - 1) . stateChar($state); $lines[] = $text; } return $lines;
}
