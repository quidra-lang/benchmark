<?php
function signalGain(array $samples, int $num, int $den): array {
    $clips = new ClipCounter(); $output = []; foreach ($samples as $x) $output[] = $clips->saturate(rdiv($x * $num, $den)); return [$output, $clips->count];
}
function signalMix(array $tracks, array $weights, int $den): array {
    $length = 0; foreach ($tracks as $track) $length = max($length, count($track)); $clips = new ClipCounter(); $output = [];
    for ($i = 0; $i < $length; $i++) { $total = 0; foreach ($tracks as $k => $track) if ($i < count($track)) $total += $weights[$k] * $track[$i]; $output[] = $clips->saturate(rdiv($total, $den)); }
    return [$output, $clips->count];
}
function signalDelay(array $samples, int $count): array { return array_merge(array_fill(0, $count, 0), $samples); }
function signalEcho(array $samples, int $delay, int $num, int $den, int $tail): array {
    $output = array_merge($samples, array_fill(0, $tail, 0)); $clips = new ClipCounter();
    for ($i = $delay; $i < count($output); $i++) $output[$i] = $clips->saturate($output[$i] + rdiv($num * $output[$i - $delay], $den));
    return [$output, $clips->count];
}
function resampledLength(int $length, int $oldRate, int $newRate): int { return intdiv(($length - 1) * $newRate, $oldRate) + 1; }
function signalResample(array $samples, int $oldRate, int $newRate): array {
    $output = []; $length = resampledLength(count($samples), $oldRate, $newRate);
    for ($j = 0; $j < $length; $j++) { $p = intdiv($j * $oldRate, $newRate); $q = $j * $oldRate % $newRate; $value = $samples[$p]; if ($q > 0) $value += rdiv(($samples[$p + 1] - $value) * $q, $newRate); $output[] = $value; }
    return $output;
}
function signalFade(array $samples, int $fadeIn, int $fadeOut): array {
    $length = count($samples); for ($i = 0; $i < $fadeIn; $i++) $samples[$i] = rdiv($samples[$i] * $i, $fadeIn);
    for ($i = $length - $fadeOut; $i < $length; $i++) $samples[$i] = rdiv($samples[$i] * ($length - 1 - $i), $fadeOut); return $samples;
}
