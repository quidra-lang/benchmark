<?php

function filterSignal(array $ecg): array
{
    $lowpass = [];
    $bandpass = [];
    $derivative = [];
    $squared = [];
    $integrated = [];
    $previous = 0;
    $beforePrevious = 0;
    $highpassSum = 0;
    $windowSum = 0;
    for ($n = 0; $n < count($ecg); $n++) {
        $current = 2 * $previous - $beforePrevious + $ecg[$n] - 2 * ($ecg[$n - 6] ?? 0) + ($ecg[$n - 12] ?? 0);
        $beforePrevious = $previous;
        $previous = $current;
        $lowpass[] = floorDiv($current, 32);
        $highpassSum += $lowpass[$n] - ($lowpass[$n - 32] ?? 0);
        $bandpass[] = ($lowpass[$n - 16] ?? 0) - floorDiv($highpassSum, 32);
        $derivative[] = floorDiv(2 * $bandpass[$n] + ($bandpass[$n - 1] ?? 0) - ($bandpass[$n - 3] ?? 0) - 2 * ($bandpass[$n - 4] ?? 0), 8);
        $squared[] = $derivative[$n] * $derivative[$n];
        $windowSum += $squared[$n] - ($squared[$n - 30] ?? 0);
        $integrated[] = intdiv($windowSum, 30);
    }
    return compact('ecg', 'lowpass', 'bandpass', 'derivative', 'squared', 'integrated');
}
