<?php

class Peak
{
    public int $number;
    public int $time;
    public int $position;
    public int $peakI;
    public int $peakF;
    public int $slope;
    public ?int $thresholdI = null;
    public ?int $thresholdF = null;
    public ?string $kind = null;

    public function __construct(int $number, int $time, int $position, int $peakI, int $peakF, int $slope)
    {
        $this->number = $number;
        $this->time = $time;
        $this->position = $position;
        $this->peakI = $peakI;
        $this->peakF = $peakF;
        $this->slope = $slope;
    }
}

function findPeaks(array $signals): array
{
    $integrated = $signals['integrated'];
    $bandpass = $signals['bandpass'];
    $derivative = $signals['derivative'];
    $peaks = [];
    $length = count($integrated);
    for ($n = 0; $n < $length; $n++) {
        if ($integrated[$n] <= 0) {
            continue;
        }
        $peak = true;
        for ($j = max(0, $n - 20); $j < $n; $j++) {
            if ($integrated[$j] >= $integrated[$n]) {
                $peak = false;
                break;
            }
        }
        if (!$peak) {
            continue;
        }
        for ($j = $n + 1; $j <= min($length - 1, $n + 20); $j++) {
            if ($integrated[$j] > $integrated[$n]) {
                $peak = false;
                break;
            }
        }
        if (!$peak) {
            continue;
        }
        $position = max(0, $n - 30);
        for ($j = $position + 1; $j <= $n; $j++) {
            if (abs($bandpass[$j]) > abs($bandpass[$position])) {
                $position = $j;
            }
        }
        $slope = 0;
        for ($j = max(0, $n - 29); $j <= $n; $j++) {
            $slope = max($slope, abs($derivative[$j]));
        }
        $peaks[] = new Peak(count($peaks) + 1, $n, $position, $integrated[$n], abs($bandpass[$position]), $slope);
    }
    return $peaks;
}

function qrsWidth(array $bandpass, int $position): int
{
    $amplitude = abs($bandpass[$position]);
    $first = $position;
    $last = $position;
    for ($j = max(0, $position - 25); $j <= min(count($bandpass) - 1, $position + 25); $j++) {
        if (4 * abs($bandpass[$j]) >= $amplitude) {
            $first = min($first, $j);
            $last = max($last, $j);
        }
    }
    return 5 * ($last - $first + 1);
}

function initialLevels(array $signals): array
{
    $maxI = 0;
    $maxF = 0;
    $sumI = 0;
    $sumF = 0;
    for ($n = 0; $n < 400; $n++) {
        $maxI = max($maxI, $signals['integrated'][$n]);
        $maxF = max($maxF, abs($signals['bandpass'][$n]));
        $sumI += $signals['integrated'][$n];
        $sumF += abs($signals['bandpass'][$n]);
    }
    return ['spki' => intdiv($maxI, 3), 'npki' => intdiv($sumI, 800), 'spkf' => intdiv($maxF, 3), 'npkf' => intdiv($sumF, 800)];
}
