<?php

function detectPicks(object $station, object $params): object
{
    $samples = $station->samples;
    $n = count($samples);
    $total = 0;
    foreach ($samples as $value) {
        $total += $value;
    }
    $mean = intdiv($total, $n);
    if ($total < 0 && $total % $n !== 0) {
        $mean--;
    }
    $energy = [];
    $absolute = [];
    $prefix = [0];
    $clippedSamples = 0;
    $peak = 0;
    foreach ($samples as $value) {
        $deviation = $value - $mean;
        $square = $deviation * $deviation;
        $energy[] = $square;
        $prefix[] = $prefix[count($prefix) - 1] + $square;
        $amplitude = abs($deviation);
        $absolute[] = $amplitude;
        $peak = max($peak, $amplitude);
        if (abs($value) >= $params->clipLevel) {
            $clippedSamples++;
        }
    }
    $picks = [];
    $triggers = 0;
    $shortTriggers = 0;
    $start = null;
    $maximumRatio = 0;
    [$onNumerator, $onDenominator] = $params->triggerOn;
    [$offNumerator, $offDenominator] = $params->triggerOff;
    $sw = $params->staWindow;
    $lw = $params->ltaWindow;
    $finish = function (int $end) use (&$picks, &$shortTriggers, &$start, &$maximumRatio, $station, $params, $energy, $absolute, $samples, $n, $sw): void {
        $duration = $end - $start;
        if ($duration < $params->minDuration) {
            $shortTriggers++;
            return;
        }
        $position = $start;
        while ($position - 1 >= $start - $sw + 1 && $energy[$position - 1] >= $params->noiseLevel) {
            $position--;
        }
        $amplitude = 0;
        $clipped = false;
        for ($j = $position; $j < min($position + $params->amplitudeWindow, $n); $j++) {
            $amplitude = max($amplitude, $absolute[$j]);
            if (abs($samples[$j]) >= $params->clipLevel) {
                $clipped = true;
            }
        }
        $sample = $station->start + $position;
        $picks[] = (object) ['station' => $station, 'sample' => $sample, 'time' => $sample / 100, 'duration' => $duration,
            'snr' => $maximumRatio, 'amplitude' => $amplitude, 'clipped' => $clipped, 'candidate' => null,
            'state' => 'unassociated', 'event' => 0, 'residual' => null];
    };
    for ($i = $sw + $lw - 1; $i < $n; $i++) {
        $sta = $prefix[$i + 1] - $prefix[$i - $sw + 1];
        $lta = $prefix[$i - $sw + 1] - $prefix[$i - $sw - $lw + 1];
        if ($start === null) {
            if ($sta * $lw * $onDenominator >= $onNumerator * $lta * $sw) {
                $start = $i;
                $maximumRatio = ($sta * $lw) / ($lta * $sw);
                $triggers++;
            }
        } elseif ($sta * $lw * $offDenominator < $offNumerator * $lta * $sw) {
            $finish($i);
            $start = null;
        } else {
            $maximumRatio = max($maximumRatio, ($sta * $lw) / ($lta * $sw));
        }
    }
    if ($start !== null) {
        $finish($n);
    }
    return (object) ['mean' => $mean, 'noise' => median($absolute), 'peak' => $peak, 'clippedSamples' => $clippedSamples,
        'triggers' => $triggers, 'shortTriggers' => $shortTriggers, 'picks' => $picks];
}
