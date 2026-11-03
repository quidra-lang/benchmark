<?php
function energy(array $samples): int { $sum = 0; foreach ($samples as $x) $sum += $x * $x; return $sum; }
function integerSqrt(int $n): int {
    $low = 0; $high = $n + 1;
    while ($high - $low > 1) { $middle = intdiv($low + $high, 2); if ($middle <= intdiv($n, $middle)) $low = $middle; else $high = $middle; } return $low;
}
function rms(array $samples): int { return integerSqrt(intdiv(energy($samples), count($samples))); }
function zeroCrossings(array $samples): int { $count = 0; for ($i = 1; $i < count($samples); $i++) if (($samples[$i - 1] < 0) !== ($samples[$i] < 0)) $count++; return $count; }
function countClipped(array $samples): int { $count = 0; foreach ($samples as $x) if ($x === -32768 || $x === 32767) $count++; return $count; }
function crestFraction(array $samples): string {
    $denominator = energy($samples); if ($denominator === 0) return 'none'; $p = peak($samples); $numerator = $p * $p * count($samples); $a = $numerator; $b = $denominator;
    while ($b !== 0) { $next = $a % $b; $a = $b; $b = $next; } return intdiv($numerator, $a) . '/' . intdiv($denominator, $a);
}
function autocorrelation(array $samples, int $lag): int { $sum = 0; for ($n = 0; $n < count($samples) - $lag; $n++) $sum += $samples[$n] * $samples[$n + $lag]; return $sum; }
function pitchLag(array $samples, int $low, int $high): ?int {
    $bestLag = $low; $bestValue = autocorrelation($samples, $low);
    for ($lag = $low + 1; $lag <= $high; $lag++) { $value = autocorrelation($samples, $lag); if ($value > $bestValue) { $bestLag = $lag; $bestValue = $value; } } return $bestValue > 0 ? $bestLag : null;
}
