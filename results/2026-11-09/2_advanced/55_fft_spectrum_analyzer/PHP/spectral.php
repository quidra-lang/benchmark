<?php

function localMaximum($values, $k)
{
    return $k > 0 && $k + 1 < count($values) && $values[$k] > $values[$k - 1] && $values[$k] > $values[$k + 1];
}

function interpolate($values, $k, $logarithmic = true)
{
    if (!localMaximum($values, $k)) {
        return ['position' => $k, 'value' => $values[$k]];
    }
    $alpha = $logarithmic ? log($values[$k - 1]) : $values[$k - 1];
    $beta = $logarithmic ? log($values[$k]) : $values[$k];
    $gamma = $logarithmic ? log($values[$k + 1]) : $values[$k + 1];
    $delta = ($alpha - $gamma) / (2 * ($alpha - 2 * $beta + $gamma));
    $value = $beta - ($alpha - $gamma) * $delta / 4;
    return ['position' => $k + $delta, 'value' => $logarithmic ? exp($value) : $value];
}

function median($values)
{
    sort($values, SORT_NUMERIC);
    $middle = intdiv(count($values), 2);
    return count($values) % 2 === 1 ? $values[$middle] : ($values[$middle - 1] + $values[$middle]) / 2;
}

function amplitudeSpectrum($signal, $window)
{
    $length = count($window['values']);
    $windowed = [];
    foreach ($window['values'] as $n => $weight) {
        $windowed[] = $signal[$n] * $weight;
    }
    $transformed = dft(asComplex($windowed));
    $amplitude = [];
    for ($k = 0; $k <= intdiv($length, 2); $k++) {
        $scale = $k === 0 || 2 * $k === $length ? 1 : 2;
        $amplitude[] = $scale * magnitude($transformed[$k]) / $window['s1'];
    }
    return ['window' => $window, 'windowed' => $windowed, 'transformed' => $transformed, 'amplitude' => $amplitude];
}

function segments($signal, $window, $hop)
{
    $length = count($window['values']);
    for ($start = 0; $start + $length <= count($signal); $start += $hop) {
        $windowed = [];
        foreach ($window['values'] as $n => $weight) {
            $windowed[] = $signal[$start + $n] * $weight;
        }
        yield ['start' => $start, 'windowed' => $windowed, 'transformed' => packedFFT($windowed)];
    }
}

function welch($first, $second, $window, $sampleRate, $inspect)
{
    $length = count($window['values']);
    $bins = intdiv($length, 2) + 1;
    $pxx = $pyy = array_fill(0, $bins, 0.0);
    $pxy = array_fill(0, $bins, [0.0, 0.0]);
    $count = 0;
    foreach (segments($first, $window, intdiv($length, 2)) as $x) {
        $windowed = [];
        foreach ($window['values'] as $n => $weight) {
            $windowed[] = $second[$x['start'] + $n] * $weight;
        }
        $y = ['windowed' => $windowed, 'transformed' => packedFFT($windowed)];
        $inspect($x);
        $inspect($y);
        for ($k = 0; $k < $bins; $k++) {
            $pxx[$k] += squared($x['transformed'][$k]);
            $pyy[$k] += squared($y['transformed'][$k]);
            $cross = multiply(conjugate($x['transformed'][$k]), $y['transformed'][$k]);
            $pxy[$k][0] += $cross[0];
            $pxy[$k][1] += $cross[1];
        }
        $count++;
    }
    $psd = $coherence = $transfer = [];
    for ($k = 0; $k < $bins; $k++) {
        $scale = $k === 0 || $k === intdiv($length, 2) ? 1 : 2;
        $psd[] = $scale * $pxx[$k] / ($count * $sampleRate * $window['s2']);
        $coherence[] = squared($pxy[$k]) / ($pxx[$k] * $pyy[$k]);
        $transfer[] = [$pxy[$k][0] / $pxx[$k], $pxy[$k][1] / $pxx[$k]];
    }
    return ['segments' => $count, 'psd' => $psd, 'coherence' => $coherence, 'transfer' => $transfer];
}
