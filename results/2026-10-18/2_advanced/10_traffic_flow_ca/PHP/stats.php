<?php
function gcd(int $a, int $b): int { while ($b !== 0) { $next = $a % $b; $a = $b; $b = $next; } return $a; }
function dec(int $numerator, int $denominator, int $places): string {
    if ($denominator === 0) return '-'; $scale = 1; for ($j = 0; $j < $places; $j++) $scale *= 10; $value = intdiv(2 * $numerator * $scale + $denominator, 2 * $denominator);
    return intdiv($value, $scale) . '.' . str_pad((string)($value % $scale), $places, '0', STR_PAD_LEFT);
}
function frac(int $numerator, int $denominator): string { if ($denominator === 0) return '-'; $divisor = gcd($numerator, $denominator); return intdiv($numerator, $divisor) . '/' . intdiv($denominator, $divisor); }
function percentile(array $times, int $q): int { return $times[intdiv($q * count($times) + 99, 100) - 1]; }
function histogramLines(array $times, int $width): array {
    $first = intdiv($times[0], $width); $last = intdiv($times[count($times) - 1], $width); $counts = array_fill(0, $last - $first + 1, 0); foreach ($times as $time) $counts[intdiv($time, $width) - $first]++;
    $peak = max($counts); $lines = []; foreach ($counts as $j => $count) { $low = ($first + $j) * $width; $high = $low + $width - 1; $stars = intdiv(80 * $count + $peak, 2 * $peak); $lines[] = "  $low-$high $count" . ($stars > 0 ? ' ' . str_repeat('*', $stars) : ''); } return $lines;
}
