<?php

require_once __DIR__ . '/signal_io.php';
require_once __DIR__ . '/fft.php';
require_once __DIR__ . '/windows.php';
require_once __DIR__ . '/spectral.php';
require_once __DIR__ . '/report.php';

function sumValues($values)
{
    $sum = 0.0;
    foreach ($values as $value) {
        $sum += $value;
    }
    return $sum;
}

function squareSum($values)
{
    $sum = 0.0;
    foreach ($values as $value) {
        $sum += $value * $value;
    }
    return $sum;
}

function indices($first, $last)
{
    $result = [];
    for ($i = $first; $i <= $last; $i++) {
        $result[] = $i;
    }
    return $result;
}

function yesNo($value)
{
    return $value ? 'yes' : 'no';
}

function maximumIndex($values, $candidates)
{
    $best = $candidates[0];
    foreach ($candidates as $k) {
        if ($values[$k] > $values[$best]) {
            $best = $k;
        }
    }
    return $best;
}

function strongestPeaks($values, $count, $eligible = null)
{
    $candidates = [];
    for ($k = 1; $k < count($values) - 1; $k++) {
        if (localMaximum($values, $k) && ($eligible === null || $eligible($k))) {
            $candidates[] = $k;
        }
    }
    usort($candidates, fn($a, $b) => ($values[$b] <=> $values[$a]) ?: ($a <=> $b));
    return array_slice($candidates, 0, $count);
}

function preprocess($signal, $sampleRate)
{
    $n = count($signal);
    $mean = sumValues($signal) / $n;
    $center = ($n - 1) / 2;
    $numerator = $denominator = 0.0;
    for ($i = 0; $i < $n; $i++) {
        $numerator += ($i - $center) * ($signal[$i] - $mean);
        $denominator += ($i - $center) * ($i - $center);
    }
    $slope = $numerator / $denominator;
    $values = [];
    $squares = $third = $fourth = $peak = 0.0;
    foreach ($signal as $i => $value) {
        $d = $value - $mean - $slope * ($i - $center);
        $values[] = $d;
        $squares += $d * $d;
        $third += $d * $d * $d;
        $fourth += $d * $d * $d * $d;
        $peak = max($peak, abs($d));
    }
    $rms = sqrt($squares / $n);
    return ['values' => $values, 'squares' => $squares, 'mean' => $mean, 'slope' => $slope * $sampleRate,
        'rms' => $rms, 'min' => min($signal), 'max' => max($signal), 'crest' => $peak / $rms,
        'skewness' => ($third / $n) / ($rms * $rms * $rms), 'kurtosis' => ($fourth / $n) / ($rms * $rms * $rms * $rms)];
}

function levelHistory($first, $second, $length)
{
    $blocks = [];
    for ($start = 0; $start + $length <= count($first); $start += $length) {
        $x = array_slice($first, $start, $length);
        $y = array_slice($second, $start, $length);
        $peak = 0.0;
        foreach ($x as $value) {
            $peak = max($peak, abs($value));
        }
        $blocks[] = ['rms1' => sqrt(squareSum($x) / $length), 'rms2' => sqrt(squareSum($y) / $length), 'peak1' => $peak];
    }
    $loudest = 0;
    for ($g = 1; $g < count($blocks); $g++) {
        if ($blocks[$g]['rms1'] > $blocks[$loudest]['rms1']) {
            $loudest = $g;
        }
    }
    return ['blocks' => $blocks, 'loudest' => $loudest];
}

function windowComparisons($signal, $params, $sampleRate)
{
    $center = $params['fundamental'] * $params['mainLength'] / $sampleRate;
    $candidates = array_values(array_filter(indices(1, intdiv($params['mainLength'], 2) - 1),
        fn($k) => abs($k - $center) <= $params['search']));
    $result = [];
    foreach (array_keys(WINDOW_COEFFICIENTS) as $name) {
        $window = makeWindow($name, $params['mainLength'], $sampleRate);
        $spectrum = amplitudeSpectrum($signal, $window);
        $bin = maximumIndex($spectrum['amplitude'], $candidates);
        $result[] = ['name' => $name, 'window' => $window, 'spectrum' => $spectrum, 'bin' => $bin,
            'binAmplitude' => $spectrum['amplitude'][$bin], 'refinedAmplitude' => interpolate($spectrum['amplitude'], $bin)['value'],
            'floorDb' => 20 * log10(median(array_slice($spectrum['amplitude'], 1, -1)))];
    }
    return $result;
}

function harmonicAnalysis($amplitude, $params, $sampleRate)
{
    $candidates = indices(1, count($amplitude) - 2);
    $harmonics = [];
    for ($h = 1; $h <= 10; $h++) {
        $center = $h * $params['fundamental'] * $params['mainLength'] / $sampleRate;
        $selected = array_values(array_filter($candidates, fn($k) => abs($k - $center) <= $params['search']));
        $bin = maximumIndex($amplitude, $selected);
        $result = interpolate($amplitude, $bin);
        $harmonics[] = ['h' => $h, 'bin' => $bin, 'target' => $h * $params['fundamental'],
            'refined' => $result['position'] * $sampleRate / $params['mainLength'], 'amplitude' => $result['value']];
    }
    $fundamental = $harmonics[0]['amplitude'];
    foreach ($harmonics as &$harmonic) {
        $harmonic['levelDb'] = 20 * log10($harmonic['amplitude'] / $fundamental);
    }
    unset($harmonic);
    $squares = 0.0;
    for ($i = 1; $i < count($harmonics); $i++) {
        $squares += $harmonics[$i]['amplitude'] * $harmonics[$i]['amplitude'];
    }
    $thd = sqrt($squares) / $fundamental;
    return ['harmonics' => $harmonics, 'thdPercent' => 100 * $thd, 'thdDb' => 20 * log10($thd)];
}

function powerAnalysis($spectrum, $harmonics, $params, $sampleRate)
{
    $amplitude = $spectrum['amplitude'];
    $bins = indices(1, count($amplitude) - 2);
    $powers = array_map(fn($value) => $value * $value / 2, $amplitude);
    $total = $fundamental = $weighted = $logSum = 0.0;
    foreach ($bins as $k) {
        $total += $powers[$k];
        if (abs($k - $harmonics[0]['bin']) <= $params['search']) {
            $fundamental += $powers[$k];
        }
        $weighted += ($k * $sampleRate / $params['mainLength']) * $powers[$k];
        $logSum += log($powers[$k]);
    }
    $enbw = $spectrum['window']['enbwBins'];
    $totalPower = $total / $enbw;
    $fundamental /= $enbw;
    $thdn = sqrt(($totalPower - $fundamental) / $fundamental);
    $centroid = $weighted / $total;
    $spreadSum = $running = 0.0;
    $rolloff = 0;
    $chosen = false;
    foreach ($bins as $k) {
        $frequency = $k * $sampleRate / $params['mainLength'];
        $spreadSum += ($frequency - $centroid) * ($frequency - $centroid) * $powers[$k];
        $running += $powers[$k];
        if (!$chosen && $running >= 0.85 * $total) {
            $rolloff = $frequency;
            $chosen = true;
        }
    }
    $spread = sqrt($spreadSum / $total);
    $flatnessDb = 10 * log10(exp($logSum / count($bins)) / ($total / count($bins)));
    $bands = [];
    for ($i = 0; $i + 1 < count($params['bands']); $i++) {
        $lower = $params['bands'][$i];
        $upper = $params['bands'][$i + 1];
        $sum = 0.0;
        foreach ($bins as $k) {
            if ($lower * $params['mainLength'] <= $k * $sampleRate && $k * $sampleRate < $upper * $params['mainLength']) {
                $sum += $powers[$k];
            }
        }
        $power = $sum / $enbw;
        $bands[] = ['lower' => $lower, 'upper' => $upper, 'power' => $power, 'percent' => 100 * $power / $totalPower];
    }
    $thirdOctave = [];
    for ($b = $params['thirdOctave'][0]; $b <= $params['thirdOctave'][1]; $b++) {
        $center = 1000 * pow(2, $b / 3);
        $lower = 1000 * pow(2, (2 * $b - 1) / 6);
        $upper = 1000 * pow(2, (2 * $b + 1) / 6);
        $count = 0;
        $sum = 0.0;
        foreach ($bins as $k) {
            $frequency = $k * $sampleRate / $params['mainLength'];
            if ($lower <= $frequency && $frequency < $upper) {
                $count++;
                $sum += $powers[$k];
            }
        }
        $thirdOctave[] = ['band' => $b, 'center' => $center, 'lower' => $lower, 'upper' => $upper,
            'bins' => $count, 'levelDb' => 10 * log10($sum / $enbw)];
    }
    return ['totalPower' => $totalPower, 'centroid' => $centroid, 'spread' => $spread, 'rolloff' => $rolloff,
        'flatnessDb' => $flatnessDb, 'bands' => $bands, 'thirdOctave' => $thirdOctave,
        'thdnPercent' => 100 * $thdn, 'thdnDb' => 20 * log10($thdn)];
}

function peakAnalysis($spectrum, $welchResult, $params, $sampleRate)
{
    $amplitude = $spectrum['amplitude'];
    $last = count($amplitude) - 1;
    $maximum = max($amplitude);
    $floor = median(array_slice($amplitude, 1, -1));
    $bins = strongestPeaks($amplitude, $params['peakCount'], fn($k) => 20 * log10($amplitude[$k] / $maximum) >= $params['threshold']);
    $peaks = [];
    foreach ($bins as $index => $bin) {
        $result = interpolate($amplitude, $bin);
        $halfPower = $amplitude[$bin] / sqrt(2);
        $right = $last;
        $left = 0;
        for ($j = $bin + 1; $j <= $last; $j++) {
            if ($amplitude[$j] <= $halfPower) {
                $right = $j - 1 + ($amplitude[$j - 1] - $halfPower) / ($amplitude[$j - 1] - $amplitude[$j]);
                break;
            }
        }
        for ($j = $bin - 1; $j >= 0; $j--) {
            if ($amplitude[$j] <= $halfPower) {
                $left = $j + 1 - ($amplitude[$j + 1] - $halfPower) / ($amplitude[$j + 1] - $amplitude[$j]);
                break;
            }
        }
        $coherenceBin = intdiv(2 * $bin * $params['welchLength'] + $params['mainLength'], 2 * $params['mainLength']);
        $peaks[] = ['rank' => $index + 1, 'bin' => $bin, 'position' => $result['position'],
            'frequency' => $bin * $sampleRate / $params['mainLength'], 'refined' => $result['position'] * $sampleRate / $params['mainLength'],
            'amplitude' => $result['value'], 'levelDb' => 20 * log10($amplitude[$bin] / $maximum),
            'phase' => phase($spectrum['transformed'][$bin]) * 180 / FFT_PI,
            'bandwidth' => ($right - $left) * $sampleRate / $params['mainLength'], 'snrDb' => 20 * log10($amplitude[$bin] / $floor),
            'coherence' => $welchResult['coherence'][$coherenceBin]];
    }
    foreach ($peaks as $index => $peak) {
        $label = 'other';
        for ($h = 1; $h <= 10; $h++) {
            if (abs($peak['position'] - $h * $params['fundamental'] * $params['mainLength'] / $sampleRate) <= $params['search']) {
                $label = 'h' . $h;
                break;
            }
        }
        if ($label === 'other') {
            [$notchFrequency, $notchWidth] = $params['notch'];
            $multiple = (int)floor($peak['refined'] / $notchFrequency + 0.5);
            if ($multiple >= 1 && abs($peak['refined'] - $multiple * $notchFrequency) <= $notchWidth) {
                $label = 'mains';
            } else {
                foreach ($peaks as $parentIndex => $parent) {
                    if ($parentIndex === $index || $amplitude[$parent['bin']] <= $amplitude[$peak['bin']]) {
                        continue;
                    }
                    foreach ($peaks as $otherIndex => $other) {
                        if ($otherIndex !== $index && $otherIndex !== $parentIndex && $amplitude[$parent['bin']] > $amplitude[$other['bin']] &&
                            abs($peak['position'] + $other['position'] - 2 * $parent['position']) <= 1) {
                            $label = 'sideband' . $parent['rank'];
                            break 2;
                        }
                    }
                }
            }
        }
        $peaks[$index]['label'] = $label;
    }
    return ['peaks' => $peaks, 'maximum' => $maximum, 'floor' => $floor];
}

function inspectPacking($segment, &$packing)
{
    $reference = radix2(asComplex($segment['windowed']));
    foreach ($segment['transformed'] as $k => $actual) {
        $error = magnitude([$actual[0] - $reference[$k][0], $actual[1] - $reference[$k][1]]);
        $packing['error'] = max($packing['error'], $error);
    }
    $packing['transforms']++;
}

function welchAnalysis($first, $second, $firstStatistics, $params, $sampleRate, $inspect)
{
    $window = makeWindow($params['welchWindow'], $params['welchLength'], $sampleRate);
    $result = welch($first, $second, $window, $sampleRate, $inspect);
    $integratedPower = sumValues($result['psd']) * $sampleRate / $params['welchLength'];
    $variance = $firstStatistics['rms'] * $firstStatistics['rms'];
    $peaks = [];
    foreach (strongestPeaks($result['psd'], 5) as $index => $bin) {
        $peaks[] = ['rank' => $index + 1, 'frequency' => $bin * $sampleRate / $params['welchLength'],
            'psdDb' => 10 * log10($result['psd'][$bin]), 'coherence' => $result['coherence'][$bin],
            'gain' => magnitude($result['transfer'][$bin]), 'phase' => phase($result['transfer'][$bin]) * 180 / FFT_PI];
    }
    return array_merge($result, ['integratedPower' => $integratedPower, 'variance' => $variance,
        'ratio' => $integratedPower / $variance, 'peaks' => $peaks]);
}

function spectrogramAnalysis($signal, $params, $sampleRate, $inspect)
{
    $window = makeWindow($params['frameWindow'], $params['frameLength'], $sampleRate);
    $frames = [];
    $maximum = 0.0;
    foreach (segments($signal, $window, $params['hop']) as $segment) {
        $inspect($segment);
        $values = array_map('magnitude', $segment['transformed']);
        $maximum = max($maximum, max($values));
        $frames[] = $values;
    }
    $levels = $track = [];
    $candidates = indices(1, intdiv($params['frameLength'], 2) - 1);
    foreach ($frames as $frame) {
        $level = [];
        foreach ($frame as $value) {
            $decibels = 20 * log10($value / $maximum);
            $level[] = (int)max(0, 9 - floor(-$decibels / $params['shadeWidth']));
        }
        $levels[] = $level;
        $bin = maximumIndex($frame, $candidates);
        $track[] = ['frequency' => $bin * $sampleRate / $params['frameLength'], 'levelDb' => 20 * log10($frame[$bin] / $maximum)];
    }
    $flux = [0.0];
    for ($t = 1; $t < count($frames); $t++) {
        $sum = 0.0;
        foreach ($frames[$t] as $k => $value) {
            $sum += max(0, $value - $frames[$t - 1][$k]);
        }
        $flux[] = $sum;
    }
    $threshold = $params['onsetFactor'] * median(array_slice($flux, 1));
    $onsets = [];
    for ($t = 1; $t < count($frames); $t++) {
        if ($flux[$t] > $threshold && $flux[$t] > $flux[$t - 1] &&
            ($t === count($frames) - 1 || $flux[$t] > $flux[$t + 1])) {
            $onsets[] = $t;
        }
    }
    $kurtosis = [];
    for ($k = 0; $k <= intdiv($params['frameLength'], 2); $k++) {
        $second = $fourth = 0.0;
        foreach ($frames as $frame) {
            $second += $frame[$k] * $frame[$k];
            $fourth += $frame[$k] * $frame[$k] * $frame[$k] * $frame[$k];
        }
        $kurtosis[] = count($frames) * $fourth / ($second * $second) - 2;
    }
    $kurtosisBin = maximumIndex($kurtosis, $candidates);
    return ['frames' => count($frames), 'maximum' => $maximum, 'levels' => $levels, 'track' => $track, 'flux' => $flux,
        'threshold' => $threshold, 'onsets' => $onsets, 'kurtosisBin' => $kurtosisBin, 'kurtosis' => $kurtosis[$kurtosisBin]];
}

function filterAnalysis($first, $second, $params, $sampleRate)
{
    $n = count($first);
    $transformed = dft(asComplex($first));
    $binsKept = $binsRemoved = 0;
    $bandSpectrum = $notchSpectrum = $envelopeSpectrum = [];
    [$notchFrequency, $notchWidth] = $params['notch'];
    foreach ($transformed as $k => $value) {
        $frequencyNumerator = min($k, $n - $k) * $sampleRate;
        if ($params['bandpass'][0] * $n <= $frequencyNumerator && $frequencyNumerator <= $params['bandpass'][1] * $n) {
            $binsKept++;
            $bandSpectrum[] = $value;
        } else {
            $bandSpectrum[] = [0.0, 0.0];
        }
        $multiple = intdiv(2 * $frequencyNumerator + $notchFrequency * $n, 2 * $notchFrequency * $n);
        if ($multiple >= 1 && abs($frequencyNumerator - $multiple * $notchFrequency * $n) <= $notchWidth * $n) {
            $binsRemoved++;
            $notchSpectrum[] = [0.0, 0.0];
        } else {
            $notchSpectrum[] = $value;
        }
        if ($k >= 1 && $k <= intdiv($n - 1, 2) && $params['envelope'][0] * $n <= $k * $sampleRate &&
            $k * $sampleRate <= $params['envelope'][1] * $n) {
            $envelopeSpectrum[] = [2 * $value[0], 2 * $value[1]];
        } else {
            $envelopeSpectrum[] = [0.0, 0.0];
        }
    }
    $bandpassed = array_map(fn($value) => $value[0], idft($bandSpectrum));
    $notched = array_map(fn($value) => $value[0], idft($notchSpectrum));
    $analytic = idft($envelopeSpectrum);
    $envelope = array_map('magnitude', $analytic);
    $envelopeMean = sumValues($envelope) / $n;
    $modulation = array_map(fn($value) => 2 * magnitude($value) / $n,
        dft(asComplex(array_map(fn($value) => $value - $envelopeMean, $envelope))));
    $upper = intdiv(($params['envelope'][1] - $params['envelope'][0]) * $n, 2 * $sampleRate);
    $envelopeBin = maximumIndex($modulation, indices(1, $upper));
    $interpolated = interpolate($modulation, $envelopeBin);
    $phases = array_map('phase', $analytic);
    $instantaneous = [];
    for ($i = 1; $i < $n; $i++) {
        $difference = $phases[$i] - $phases[$i - 1];
        if ($difference <= -FFT_PI) {
            $difference += 2 * FFT_PI;
        }
        if ($difference > FFT_PI) {
            $difference -= 2 * FFT_PI;
        }
        $instantaneous[] = $difference * $sampleRate / (2 * FFT_PI);
    }
    $instantaneousMean = sumValues($instantaneous) / ($n - 1);
    $squares = 0.0;
    foreach ($instantaneous as $value) {
        $squares += ($value - $instantaneousMean) * ($value - $instantaneousMean);
    }
    $instantaneousStd = sqrt($squares / ($n - 1));
    $smoothed = convolution($second, $params['fir']);
    $gain = [0.0, 0.0];
    foreach ($params['fir'] as $j => $coefficient) {
        $rotation = rot(2 * FFT_PI * $params['fundamental'] * $j / $sampleRate);
        $gain[0] += $coefficient * $rotation[0];
        $gain[1] += $coefficient * $rotation[1];
    }
    $bandSquares = squareSum($bandpassed);
    return ['bandpassed' => $bandpassed, 'notched' => $notched, 'smoothed' => $smoothed, 'envelope' => $envelope,
        'binsKept' => $binsKept, 'binsRemoved' => $binsRemoved, 'bandRms' => sqrt($bandSquares / $n),
        'energyRatio' => $bandSquares / squareSum($first), 'notchRms' => sqrt(squareSum($notched) / $n),
        'firDcGain' => sumValues($params['fir']), 'firGainDb' => 20 * log10(magnitude($gain)),
        'firRms' => sqrt(squareSum(array_slice($smoothed, 0, $n)) / $n), 'envelopeMean' => $envelopeMean,
        'envelopeBin' => $envelopeBin, 'envelopeFrequency' => $interpolated['position'] * $sampleRate / $n,
        'envelopeAmplitude' => $interpolated['value'], 'depth' => $interpolated['value'] / $envelopeMean,
        'instantaneousMean' => $instantaneousMean, 'instantaneousStd' => $instantaneousStd];
}

function pitchAnalysis($amplitude, $bandpassed, $params, $sampleRate)
{
    [$low, $high] = $params['pitch'];
    $lagLow = intdiv($sampleRate + $high - 1, $high);
    $lagHigh = intdiv($sampleRate, $low);
    $scores = array_fill(0, count($amplitude), 0.0);
    $candidates = [];
    for ($k = 1; 5 * $k <= count($amplitude) - 1; $k++) {
        if ($low * $params['mainLength'] > $k * $sampleRate || $k * $sampleRate > $high * $params['mainLength']) {
            continue;
        }
        for ($r = 1; $r <= 5; $r++) {
            $scores[$k] += log($amplitude[$r * $k]);
        }
        $candidates[] = $k;
    }
    $hpsBin = maximumIndex($scores, $candidates);
    $transformed = radix2(asComplex($bandpassed, pow2(2 * count($bandpassed) - 1)));
    $power = array_map(fn($value) => [squared($value), 0.0], $transformed);
    $correlation = array_map(fn($value) => $value[0], radix2($power, true));
    $lag = maximumIndex($correlation, indices($lagLow, $lagHigh));
    $refined = interpolate($correlation, $lag, false);
    $crossings = 0;
    for ($i = 1; $i < count($bandpassed); $i++) {
        if ($bandpassed[$i - 1] < 0 && $bandpassed[$i] >= 0) {
            $crossings++;
        }
    }
    return ['lagLow' => $lagLow, 'lagHigh' => $lagHigh, 'hpsBin' => $hpsBin,
        'hpsFrequency' => $hpsBin * $sampleRate / $params['mainLength'], 'lag' => $lag, 'period' => $refined['position'],
        'frequency' => $sampleRate / $refined['position'], 'strength' => $refined['value'] / $correlation[0],
        'crossings' => $crossings, 'crossingFrequency' => $crossings * $sampleRate / count($bandpassed)];
}

function zoomAnalysis($spectrum, $params, $sampleRate)
{
    [$low, $high, $count] = $params['zoom'];
    $step = ($high - $low) / ($count - 1);
    $transformed = chirpZ($spectrum['windowed'], $low, $step, $count, $sampleRate);
    $amplitude = array_map(fn($value) => 2 * magnitude($value) / $spectrum['window']['s1'], $transformed);
    $peaks = [];
    foreach (strongestPeaks($amplitude, 3) as $index => $bin) {
        $result = interpolate($amplitude, $bin);
        $peaks[] = ['rank' => $index + 1, 'frequency' => $low + $result['position'] * $step, 'amplitude' => $result['value']];
    }
    return ['step' => $step, 'peaks' => $peaks];
}

function correlationPeak($values, $maximumLag, $sampleRate)
{
    $at = fn($lag) => $values[$lag < 0 ? $lag + count($values) : $lag];
    $lag = -$maximumLag;
    for ($candidate = -$maximumLag + 1; $candidate <= $maximumLag; $candidate++) {
        if ($at($candidate) > $at($lag) || ($at($candidate) === $at($lag) &&
            (abs($candidate) < abs($lag) || (abs($candidate) === abs($lag) && $candidate < $lag)))) {
            $lag = $candidate;
        }
    }
    $refined = interpolate([$at($lag - 1), $at($lag), $at($lag + 1)], 1, false);
    $refinedLag = $lag + ($refined['position'] - 1);
    return ['lag' => $lag, 'refinedLag' => $refinedLag, 'delayMs' => 1000 * $refinedLag / $sampleRate, 'value' => $at($lag)];
}

function crossCorrelation($first, $second, $params, $sampleRate)
{
    $length = pow2(2 * count($first) - 1);
    $x = radix2(asComplex($first, $length));
    $y = radix2(asComplex($second, $length));
    $cross = $normalized = [];
    foreach ($x as $k => $value) {
        $entry = multiply(conjugate($value), $y[$k]);
        $cross[] = $entry;
        $magnitude = magnitude($entry);
        $normalized[] = [$entry[0] / $magnitude, $entry[1] / $magnitude];
    }
    $raw = array_map(fn($value) => $value[0], radix2($cross, true));
    $phat = array_map(fn($value) => $value[0], radix2($normalized, true));
    $ordinary = correlationPeak($raw, $params['maxLag'], $sampleRate);
    $ordinary['coefficient'] = $ordinary['value'] / sqrt(squareSum($first) * squareSum($second));
    return ['ordinary' => $ordinary, 'phat' => correlationPeak($phat, $params['maxLag'], $sampleRate)];
}

function checkCalculations($spectrum, $peaks, $second, $smoothed, $params, $packing)
{
    $inverse = idft($spectrum['transformed']);
    $inverseError = 0.0;
    foreach ($inverse as $n => $value) {
        $inverseError = max($inverseError, magnitude([$value[0] - $spectrum['windowed'][$n], $value[1]]));
    }
    $timePower = squareSum($spectrum['windowed']);
    $frequencyPower = 0.0;
    foreach ($spectrum['transformed'] as $value) {
        $frequencyPower += squared($value);
    }
    $parsevalError = abs($timePower - $frequencyPower / $params['mainLength']) / $timePower;
    $firError = 0.0;
    foreach ($smoothed as $n => $value) {
        $direct = 0.0;
        for ($j = max(0, $n - count($params['fir']) + 1); $j <= min(count($second) - 1, $n); $j++) {
            $direct += $second[$j] * $params['fir'][$n - $j];
        }
        $firError = max($firError, abs($direct - $value));
    }
    $spotError = 0.0;
    foreach ($peaks as $peak) {
        $direct = [0.0, 0.0];
        for ($n = 0; $n < $params['mainLength']; $n++) {
            $rotation = rot(2 * FFT_PI * (($peak['bin'] * $n) % $params['mainLength']) / $params['mainLength']);
            $direct[0] += $spectrum['windowed'][$n] * $rotation[0];
            $direct[1] += $spectrum['windowed'][$n] * $rotation[1];
        }
        $transformed = $spectrum['transformed'][$peak['bin']];
        $spotError = max($spotError, magnitude([$direct[0] - $transformed[0], $direct[1] - $transformed[1]]));
    }
    $status = fn($error) => $error <= 1e-6 ? 'ok' : 'failed';
    return ['inverse' => $status($inverseError), 'parseval' => $status($parsevalError), 'packing' => $status($packing['error']),
        'transforms' => $packing['transforms'], 'fir' => $status($firError), 'spot' => $status($spotError)];
}

function diagnose($harmonics, $peaks, $filters, $spectrogram)
{
    $ratio = $harmonics[1]['amplitude'] / $harmonics[0]['amplitude'];
    $harmonicCount = 0;
    foreach (array_slice($harmonics, 2) as $harmonic) {
        if ($harmonic['levelDb'] >= -30) {
            $harmonicCount++;
        }
    }
    $mains = null;
    foreach ($peaks as $peak) {
        if ($peak['label'] === 'mains') {
            $mains = $peak;
            break;
        }
    }
    $misalignment = $ratio >= 0.5;
    $looseness = $harmonicCount >= 3;
    $bearing = $filters['depth'] >= 0.2;
    $electrical = $mains !== null && $mains['levelDb'] >= -20;
    $transient = count($spectrogram['onsets']) > 0;
    $findings = 0;
    foreach ([$misalignment, $looseness, $bearing, $electrical, $transient] as $finding) {
        if ($finding) {
            $findings++;
        }
    }
    return ['ratio' => $ratio, 'harmonicCount' => $harmonicCount, 'mains' => $mains, 'misalignment' => $misalignment,
        'looseness' => $looseness, 'bearing' => $bearing, 'electrical' => $electrical, 'transient' => $transient,
        'findings' => $findings, 'status' => $findings === 0 ? 'normal' : ($findings === 1 ? 'warning' : 'alarm')];
}

function peaksLines($result, $params, $sampleRate)
{
    $lines = ['length=' . $params['mainLength'] . ' window=' . $params['mainWindow'] . ' resolution=' . fixed($sampleRate / $params['mainLength']) .
        ' threshold_db=' . fixed($params['threshold']), 'max_amplitude=' . fixed($result['maximum']) . ' noise_floor=' . fixed($result['floor']) .
        ' noise_floor_db=' . fixed(20 * log10($result['floor'])), 'peaks=' . count($result['peaks'])];
    foreach ($result['peaks'] as $peak) {
        $lines[] = $peak['rank'] . ' bin=' . $peak['bin'] . ' frequency=' . fixed($peak['frequency']) . ' refined=' . fixed($peak['refined']) .
            ' amplitude=' . fixed($peak['amplitude']) . ' level_db=' . fixed($peak['levelDb']) . ' phase=' . fixed($peak['phase']) .
            ' bandwidth=' . fixed($peak['bandwidth']) . ' snr_db=' . fixed($peak['snrDb']) . ' coherence=' . fixed($peak['coherence']) . ' label=' . $peak['label'];
    }
    return $lines;
}

function spectrogramLines($result, $params, $sampleRate)
{
    $lines = ['frames=' . $result['frames'] . ' bins=' . (intdiv($params['frameLength'], 2) + 1) . ' frame_length=' . $params['frameLength'] .
        ' hop=' . $params['hop'] . ' window=' . $params['frameWindow'] . ' band_db=' . $params['shadeWidth'] . ' max_db=' . fixed(20 * log10($result['maximum']))];
    foreach (shadeLines($result['levels'], $sampleRate, $params['frameLength']) as $line) {
        $lines[] = $line;
    }
    $lines[] = 'track';
    foreach ($result['track'] as $t => $frame) {
        $lines[] = 'frame=' . $t . ' time=' . fixed($t * $params['hop'] / $sampleRate) .
            ' frequency=' . fixed($frame['frequency']) . ' level_db=' . fixed($frame['levelDb']);
    }
    $lines[] = 'onsets=' . count($result['onsets']) . ' threshold=' . fixed($result['threshold']);
    foreach ($result['onsets'] as $t) {
        $lines[] = 'frame=' . $t . ' time=' . fixed($t * $params['hop'] / $sampleRate) . ' flux=' . fixed($result['flux'][$t]);
    }
    $lines[] = 'kurtosis bin=' . $result['kurtosisBin'] . ' frequency=' . fixed($result['kurtosisBin'] * $sampleRate / $params['frameLength']) .
        ' value=' . fixed($result['kurtosis']);
    return $lines;
}

function analysisReport($analysis)
{
    $input = $analysis['input'];
    $params = $input['params'];
    $sampleRate = $input['sampleRate'];
    $count = $input['count'];
    $channels = $analysis['channels'];
    $levels = $analysis['levels'];
    $windows = $analysis['windows'];
    $harmonic = $analysis['harmonic'];
    $power = $analysis['power'];
    $welchResult = $analysis['welchResult'];
    $filters = $analysis['filters'];
    $pitch = $analysis['pitch'];
    $zoom = $analysis['zoom'];
    $correlation = $analysis['correlation'];
    $checks = $analysis['checks'];
    $diagnosis = $analysis['diagnosis'];
    $spectrogram = $analysis['spectrogram'];
    $peaks = $analysis['peaks'];
    $lines = ['[signal]', 'sample_rate=' . $sampleRate . ' samples=' . $count . ' duration=' . fixed($count / $sampleRate)];
    foreach ($channels as $i => $channel) {
        $lines[] = 'channel=' . ($i + 1) . ' mean=' . fixed($channel['mean']) . ' slope=' . fixed($channel['slope']) .
            ' rms=' . fixed($channel['rms']) . ' min=' . fixed($channel['min']) . ' max=' . fixed($channel['max']) .
            ' crest=' . fixed($channel['crest']) . ' skewness=' . fixed($channel['skewness']) . ' kurtosis=' . fixed($channel['kurtosis']);
    }
    $lines[] = '[levels]';
    $lines[] = 'block_length=' . $params['blockLength'] . ' blocks=' . count($levels['blocks']) . ' loudest=' . $levels['loudest'];
    foreach ($levels['blocks'] as $g => $block) {
        $lines[] = 'block=' . $g . ' time=' . fixed($g * $params['blockLength'] / $sampleRate) . ' rms1=' . fixed($block['rms1']) .
            ' rms2=' . fixed($block['rms2']) . ' peak1=' . fixed($block['peak1']);
    }
    $lines[] = '[windows]';
    foreach ($windows as $comparison) {
        $window = $comparison['window'];
        $lines[] = 'name=' . $comparison['name'] . ' coherent_gain=' . fixed($window['coherentGain']) . ' enbw_bins=' . fixed($window['enbwBins']) .
            ' enbw_hz=' . fixed($window['enbwHz']) . ' scalloping_db=' . fixed($window['scallopingDb']) . ' fundamental_bin=' . $comparison['bin'] .
            ' bin_amplitude=' . fixed($comparison['binAmplitude']) . ' refined_amplitude=' . fixed($comparison['refinedAmplitude']) .
            ' floor_db=' . fixed($comparison['floorDb']);
    }
    $radix = isPowerOfTwo($params['mainLength']);
    $lines[] = '[main]';
    $lines[] = 'length=' . $params['mainLength'] . ' window=' . $params['mainWindow'] . ' method=' . ($radix ? 'radix2' : 'bluestein') .
        ' transform_size=' . ($radix ? $params['mainLength'] : pow2(2 * $params['mainLength'] - 1)) . ' resolution=' . fixed($sampleRate / $params['mainLength']);
    $lines[] = 'total_power=' . fixed($power['totalPower']) . ' centroid=' . fixed($power['centroid']) . ' spread=' . fixed($power['spread']) .
        ' rolloff=' . fixed($power['rolloff']) . ' flatness_db=' . fixed($power['flatnessDb']);
    $lines[] = '[bands]';
    foreach ($power['bands'] as $band) {
        $lines[] = 'range=' . $band['lower'] . '-' . $band['upper'] . ' power=' . fixed($band['power']) . ' percent=' . fixed($band['percent']);
    }
    $lines[] = '[third_octave]';
    foreach ($power['thirdOctave'] as $band) {
        $lines[] = 'band=' . $band['band'] . ' center=' . fixed($band['center']) . ' lower=' . fixed($band['lower']) .
            ' upper=' . fixed($band['upper']) . ' bins=' . $band['bins'] . ' level_db=' . fixed($band['levelDb']);
    }
    $lines[] = '[harmonics]';
    $lines[] = 'fundamental=' . fixed($params['fundamental']) . ' search=' . $params['search'];
    foreach ($harmonic['harmonics'] as $item) {
        $lines[] = 'h=' . $item['h'] . ' target=' . fixed($item['target']) . ' bin=' . $item['bin'] .
            ' refined=' . fixed($item['refined']) . ' amplitude=' . fixed($item['amplitude']) . ' level_db=' . fixed($item['levelDb']);
    }
    $lines[] = 'thd_percent=' . fixed($harmonic['thdPercent']) . ' thd_db=' . fixed($harmonic['thdDb']);
    $lines[] = 'thdn_percent=' . fixed($power['thdnPercent']) . ' thdn_db=' . fixed($power['thdnDb']);
    $lines[] = '[pitch]';
    $lines[] = 'range=' . $params['pitch'][0] . '-' . $params['pitch'][1] . ' lags=' . $pitch['lagLow'] . '-' . $pitch['lagHigh'];
    $lines[] = 'hps bin=' . $pitch['hpsBin'] . ' order=5 frequency=' . fixed($pitch['hpsFrequency']);
    $lines[] = 'autocorrelation lag=' . $pitch['lag'] . ' period=' . fixed($pitch['period']) . ' frequency=' . fixed($pitch['frequency']) . ' strength=' . fixed($pitch['strength']);
    $lines[] = 'zero_crossing count=' . $pitch['crossings'] . ' frequency=' . fixed($pitch['crossingFrequency']);
    $lines[] = '[zoom]';
    $lines[] = 'band=' . $params['zoom'][0] . '-' . $params['zoom'][1] . ' points=' . $params['zoom'][2] . ' step=' . fixed($zoom['step']);
    foreach ($zoom['peaks'] as $peak) {
        $lines[] = 'peak=' . $peak['rank'] . ' frequency=' . fixed($peak['frequency']) . ' amplitude=' . fixed($peak['amplitude']);
    }
    $lines[] = '[welch]';
    $lines[] = 'segment_length=' . $params['welchLength'] . ' segments=' . $welchResult['segments'] . ' window=' . $params['welchWindow'] .
        ' resolution=' . fixed($sampleRate / $params['welchLength']);
    $lines[] = 'integrated_power=' . fixed($welchResult['integratedPower']) . ' variance=' . fixed($welchResult['variance']) . ' ratio=' . fixed($welchResult['ratio']);
    foreach ($welchResult['peaks'] as $peak) {
        $lines[] = 'peak=' . $peak['rank'] . ' frequency=' . fixed($peak['frequency']) . ' psd_db=' . fixed($peak['psdDb']) .
            ' coherence=' . fixed($peak['coherence']) . ' gain=' . fixed($peak['gain']) . ' phase=' . fixed($peak['phase']);
    }
    $lines[] = '[filter]';
    $lines[] = 'bandpass=' . $params['bandpass'][0] . '-' . $params['bandpass'][1] . ' bins_kept=' . $filters['binsKept'] .
        ' rms=' . fixed($filters['bandRms']) . ' energy_ratio=' . fixed($filters['energyRatio']);
    $lines[] = 'notch=' . $params['notch'][0] . ' width=' . $params['notch'][1] . ' bins_removed=' . $filters['binsRemoved'] . ' rms=' . fixed($filters['notchRms']);
    $lines[] = 'fir_taps=' . count($params['fir']) . ' dc_gain=' . fixed($filters['firDcGain']) .
        ' gain_at_fundamental_db=' . fixed($filters['firGainDb']) . ' rms=' . fixed($filters['firRms']);
    $lines[] = '[envelope]';
    $lines[] = 'band=' . $params['envelope'][0] . '-' . $params['envelope'][1] . ' mean=' . fixed($filters['envelopeMean']) .
        ' bin=' . $filters['envelopeBin'] . ' frequency=' . fixed($filters['envelopeFrequency']) .
        ' amplitude=' . fixed($filters['envelopeAmplitude']) . ' depth=' . fixed($filters['depth']);
    $lines[] = 'instantaneous_frequency mean=' . fixed($filters['instantaneousMean']) . ' std=' . fixed($filters['instantaneousStd']);
    $lines[] = '[correlation]';
    $ordinary = $correlation['ordinary'];
    $phat = $correlation['phat'];
    $lines[] = 'max_lag=' . $params['maxLag'] . ' lag=' . $ordinary['lag'] . ' refined_lag=' . fixed($ordinary['refinedLag']) .
        ' delay_ms=' . fixed($ordinary['delayMs']) . ' coefficient=' . fixed($ordinary['coefficient']);
    $lines[] = 'phat_lag=' . $phat['lag'] . ' refined_lag=' . fixed($phat['refinedLag']) . ' delay_ms=' . fixed($phat['delayMs']);
    $lines[] = '[checks]';
    $lines[] = 'inverse_roundtrip=' . $checks['inverse'];
    $lines[] = 'parseval=' . $checks['parseval'];
    $lines[] = 'real_packing=' . $checks['packing'] . ' transforms=' . $checks['transforms'];
    $lines[] = 'fir_fft_vs_direct=' . $checks['fir'];
    $lines[] = 'dft_spot_check=' . $checks['spot'] . ' bins=' . count($peaks['peaks']);
    $lines[] = '[diagnosis]';
    $lines[] = 'misalignment=' . yesNo($diagnosis['misalignment']) . ' ratio=' . fixed($diagnosis['ratio']);
    $lines[] = 'looseness=' . yesNo($diagnosis['looseness']) . ' harmonics=' . $diagnosis['harmonicCount'];
    $lines[] = 'bearing=' . yesNo($diagnosis['bearing']) . ' depth=' . fixed($filters['depth']);
    $lines[] = 'electrical=' . yesNo($diagnosis['electrical']) . ' level_db=' . ($diagnosis['mains'] === null ? 'none' : fixed($diagnosis['mains']['levelDb']));
    $lines[] = 'transient=' . yesNo($diagnosis['transient']) . ' onsets=' . count($spectrogram['onsets']);
    $lines[] = 'status=' . $diagnosis['status'] . ' findings=' . $diagnosis['findings'];
    return $lines;
}

function main()
{
    $input = readInput();
    $sampleRate = $input['sampleRate'];
    $params = $input['params'];
    $count = $input['count'];
    $channels = array_map(fn($signal) => preprocess($signal, $sampleRate), $input['channels']);
    [$first, $second] = [$channels[0]['values'], $channels[1]['values']];
    $levels = levelHistory($first, $second, $params['blockLength']);
    $windows = windowComparisons($first, $params, $sampleRate);
    $spectrum = null;
    foreach ($windows as $comparison) {
        if ($comparison['name'] === $params['mainWindow']) {
            $spectrum = $comparison['spectrum'];
            break;
        }
    }
    $harmonic = harmonicAnalysis($spectrum['amplitude'], $params, $sampleRate);
    $power = powerAnalysis($spectrum, $harmonic['harmonics'], $params, $sampleRate);
    $packing = ['error' => 0.0, 'transforms' => 0];
    $inspect = function ($segment) use (&$packing) {
        inspectPacking($segment, $packing);
    };
    $welchResult = welchAnalysis($first, $second, $channels[0], $params, $sampleRate, $inspect);
    $peaks = peakAnalysis($spectrum, $welchResult, $params, $sampleRate);
    $spectrogram = spectrogramAnalysis($first, $params, $sampleRate, $inspect);
    $filters = filterAnalysis($first, $second, $params, $sampleRate);
    $pitch = pitchAnalysis($spectrum['amplitude'], $filters['bandpassed'], $params, $sampleRate);
    $zoom = zoomAnalysis($spectrum, $params, $sampleRate);
    $correlation = crossCorrelation($first, $second, $params, $sampleRate);
    $checks = checkCalculations($spectrum, $peaks['peaks'], $second, $filters['smoothed'], $params, $packing);
    $diagnosis = diagnose($harmonic['harmonics'], $peaks['peaks'], $filters, $spectrogram);
    $report = analysisReport(['input' => $input, 'channels' => $channels, 'levels' => $levels, 'windows' => $windows,
        'harmonic' => $harmonic, 'power' => $power, 'peaks' => $peaks, 'welchResult' => $welchResult,
        'spectrogram' => $spectrogram, 'filters' => $filters, 'pitch' => $pitch, 'zoom' => $zoom,
        'correlation' => $correlation, 'checks' => $checks, 'diagnosis' => $diagnosis]);
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    $rows = [['frequency', 'amplitude']];
    foreach ($spectrum['amplitude'] as $k => $value) {
        $rows[] = [fixed($k * $sampleRate / $params['mainLength']), fixed($value)];
    }
    writeCsv('spectrum.csv', $rows);
    writeLines('peaks.txt', peaksLines($peaks, $params, $sampleRate));
    $rows = [['frequency', 'psd_db']];
    foreach ($welchResult['psd'] as $k => $value) {
        $rows[] = [fixed($k * $sampleRate / $params['welchLength']), fixed(10 * log10($value))];
    }
    writeCsv('welch_psd.csv', $rows);
    writeLines('spectrogram.txt', spectrogramLines($spectrogram, $params, $sampleRate));
    $rows = [['index', 'bandpass', 'notched', 'smoothed', 'envelope']];
    for ($i = 0; $i < $count; $i++) {
        $rows[] = [$i, fixed($filters['bandpassed'][$i]), fixed($filters['notched'][$i]),
            fixed($filters['smoothed'][$i]), fixed($filters['envelope'][$i])];
    }
    writeCsv('filtered.csv', $rows);
    writeLines('report.txt', $report);
}

main();
