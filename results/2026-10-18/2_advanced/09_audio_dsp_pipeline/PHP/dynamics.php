<?php
function envelope(array $samples, int $attack, int $release): array {
    $levels = []; $level = 0; foreach ($samples as $x) { $magnitude = min(abs($x), 32767); $coefficient = $magnitude > $level ? $attack : $release; $level += rdiv(($magnitude - $level) * $coefficient, 32768); $levels[] = $level; } return $levels;
}
function normalizeSignal(array $samples, int $target): array {
    $sourcePeak = peak($samples); return [$sourcePeak === 0 ? $samples : array_map(fn($x) => rdiv($x * $target, $sourcePeak), $samples), $sourcePeak];
}
function gateSignal(array $samples, int $threshold, int $hold): array {
    $output = []; $muted = 0; $last = null;
    foreach ($samples as $i => $x) { if (abs($x) >= $threshold) $last = $i; if ($last !== null && $i - $last <= $hold) $output[] = $x; else { $output[] = 0; $muted++; } } return [$output, $muted];
}
function compressSignal(array $samples, int $threshold, int $ratioNum, int $ratioDen, int $attack, int $release): array {
    $levels = envelope($samples, $attack, $release); $output = []; $gain = $minimum = 32768; $reduced = 0;
    foreach ($samples as $n => $x) {
        $level = $levels[$n]; $target = $level > $threshold ? rdiv(($threshold + rdiv(($level - $threshold) * $ratioDen, $ratioNum)) * 32768, $level) : 32768;
        $gain = $target < $gain ? $target : $gain + rdiv(($target - $gain) * $release, 32768);
        $minimum = min($minimum, $gain); if ($gain < 32768) $reduced++; $output[] = rdiv($x * $gain, 32768);
    } return [$output, $minimum, $reduced];
}
