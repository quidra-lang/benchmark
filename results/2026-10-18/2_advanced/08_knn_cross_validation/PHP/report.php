<?php
function fixed(float $value, int $places = 4): string {
    $text = number_format($value, $places, '.', ''); return str_starts_with($text, '-') && (float)$text == 0 ? substr($text, 1) : $text;
}
function fourDecimal(float $value): float { return round($value, 4, PHP_ROUND_HALF_EVEN); }
function ratio(int $numerator, int $denominator): string { return "$numerator/$denominator " . fixed($numerator / $denominator); }
function fraction(int $numerator, int $denominator): string {
    if ($denominator === 0) return '- -';
    $a = abs($numerator); $b = $denominator; while ($b !== 0) { $next = $a % $b; $a = $b; $b = $next; }
    return intdiv($numerator, $a) . '/' . intdiv($denominator, $a) . ' ' . fixed($numerator / $denominator);
}
function writeLines(string $name, array $lines): void { file_put_contents('output/' . $name, implode("\n", $lines) . "\n"); }
function joinParts(array $parts): array {
    $lines = []; foreach ($parts as $part) { if ($lines) $lines[] = ''; array_push($lines, ...$part); } return $lines;
}
