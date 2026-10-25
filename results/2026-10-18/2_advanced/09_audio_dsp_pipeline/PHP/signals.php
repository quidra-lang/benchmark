<?php
final class Signal {
    public function __construct(public readonly string $name, public readonly int $rate, public readonly array $samples, public readonly string $origin = 'input', public readonly array $ingredients = []) {}
}
function floorDiv(int $a, int $b): int { $q = intdiv($a, $b); return $a % $b !== 0 && ($a < 0) !== ($b < 0) ? $q - 1 : $q; }
function rdiv(int $a, int $b): int { return floorDiv(2 * $a + $b, 2 * $b); }
function peak(array $samples): int { $peak = 0; foreach ($samples as $sample) $peak = max($peak, abs($sample)); return $peak; }
final class ClipCounter {
    public int $count = 0;
    public function saturate(int $value): int { $limited = max(-32768, min(32767, $value)); if ($limited !== $value) $this->count++; return $limited; }
}
function readSignals(): array {
    $lines = file('input/signals.txt', FILE_IGNORE_NEW_LINES); $signals = []; $index = 0;
    while ($index < count($lines)) {
        $header = explode(' ', $lines[$index++]); $samples = []; $count = (int)$header[3];
        while (count($samples) < $count) array_push($samples, ...array_map('intval', explode(' ', $lines[$index++])));
        $signals[] = new Signal($header[1], (int)$header[2], $samples);
    }
    return $signals;
}
function formatSignal(Signal $signal): array {
    $lines = ["SIGNAL $signal->name $signal->rate " . count($signal->samples)];
    foreach (array_chunk($signal->samples, 16) as $chunk) $lines[] = implode(' ', $chunk); return $lines;
}
function impulse(int $count, int $position, int $amplitude): array { $samples = array_fill(0, $count, 0); $samples[$position] = $amplitude; return $samples; }
function stepSignal(int $count, int $position, int $amplitude): array { return array_merge(array_fill(0, $position, 0), array_fill(0, $count - $position, $amplitude)); }
function noise(int $count, int $seed): array {
    $samples = []; for ($i = 0; $i < $count; $i++) { $seed = 48271 * $seed % 2147483647; $samples[] = $seed % 65536 - 32768; } return $samples;
}
