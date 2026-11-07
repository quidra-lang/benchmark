<?php
function firFilter(array $samples, int $divisor, array $taps): array {
    $clips = new ClipCounter(); $output = []; foreach ($samples as $n => $x) { $total = 0; for ($k = 0; $k < min(count($taps), $n + 1); $k++) $total += $taps[$k] * $samples[$n - $k]; $output[] = $clips->saturate(floorDiv($total, $divisor)); }
    return [$output, $clips->count];
}
function biquadFilter(array $samples, array $sections): array {
    $clips = new ClipCounter(); foreach ($sections as [$b0, $b1, $b2, $a1, $a2]) {
        $output = []; $u1 = $u2 = $v1 = $v2 = 0;
        foreach ($samples as $u) { $v = $clips->saturate(floorDiv($b0 * $u + $b1 * $u1 + $b2 * $u2 - $a1 * $v1 - $a2 * $v2, 16384)); $output[] = $v; $u2 = $u1; $u1 = $u; $v2 = $v1; $v1 = $v; }
        $samples = $output;
    } return [$samples, $clips->count];
}
function movingAverage(array $samples, int $width): array {
    $output = []; $total = 0; foreach ($samples as $n => $x) { $total += $x; if ($n >= $width) $total -= $samples[$n - $width]; $output[] = rdiv($total, $width); } return $output;
}
function dcBlock(array $samples, int $num, int $den): array {
    $clips = new ClipCounter(); $output = []; $previousInput = $previousOutput = 0;
    foreach ($samples as $x) { $previousOutput = $clips->saturate($x - $previousInput + rdiv($num * $previousOutput, $den)); $previousInput = $x; $output[] = $previousOutput; } return [$output, $clips->count];
}
