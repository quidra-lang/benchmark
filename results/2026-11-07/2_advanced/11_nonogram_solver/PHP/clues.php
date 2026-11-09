<?php
function isClueLine(string $text): bool { return $text !== '' && strspn($text, '0123456789 ') === strlen($text); }
function parseClue(string $text): ?array {
    if ($text === '0') return []; $clue = []; foreach (explode(' ', $text) as $token) { if (!preg_match('/\A[1-9][0-9]?\z/', $token)) return null; $clue[] = (int)$token; } return $clue;
}
function runClue(array $cells): array {
    $clue = []; $run = 0; foreach ($cells as $state) { if ($state === CELL_FILLED) $run++; elseif ($run > 0) { $clue[] = $run; $run = 0; } } if ($run > 0) $clue[] = $run; return $clue;
}
function spaced(array $clue): string { return $clue ? implode(' ', $clue) : '0'; }
function commaClue(array $clue): string { return $clue ? implode(',', $clue) : '0'; }
function clueSpan(array $clue): int { return array_sum($clue) + count($clue) - 1; }
function fitsClue(array $clue, int $length): bool { return clueSpan($clue) <= $length; }
