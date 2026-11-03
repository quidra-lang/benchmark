<?php

const WINDOW_COEFFICIENTS = [
    'rectangular' => [1], 'hann' => [0.5, 0.5], 'hamming' => [0.54, 0.46],
    'blackman' => [0.42, 0.5, 0.08], 'flattop' => [0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368]
];

function makeWindow($name, $length, $sampleRate)
{
    $values = [];
    for ($n = 0; $n < $length; $n++) {
        $total = 0.0;
        foreach (WINDOW_COEFFICIENTS[$name] as $j => $coefficient) {
            $total += ($j % 2 === 0 ? 1 : -1) * $coefficient * cos(2 * FFT_PI * $j * $n / $length);
        }
        $values[] = $total;
    }
    $s1 = $s2 = 0.0;
    $halfBin = [0.0, 0.0];
    foreach ($values as $n => $value) {
        $s1 += $value;
        $s2 += $value * $value;
        $rotation = rot(FFT_PI * $n / $length);
        $halfBin[0] += $value * $rotation[0];
        $halfBin[1] += $value * $rotation[1];
    }
    $coherentGain = $s1 / $length;
    $enbwBins = $length * $s2 / ($s1 * $s1);
    return ['name' => $name, 'values' => $values, 's1' => $s1, 's2' => $s2, 'coherentGain' => $coherentGain,
        'enbwBins' => $enbwBins, 'enbwHz' => $enbwBins * $sampleRate / $length,
        'scallopingDb' => -20 * log10(magnitude($halfBin) / $s1)];
}
