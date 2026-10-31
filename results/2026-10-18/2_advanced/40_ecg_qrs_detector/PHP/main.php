<?php

require_once __DIR__ . '/report.php';
require_once __DIR__ . '/signal_io.php';
require_once __DIR__ . '/filters.php';
require_once __DIR__ . '/detector.php';
require_once __DIR__ . '/hrv.php';

const LABELS = ['N', 'V', 'A'];
const CLASSES = ['qrs', 'searchback', 'twave', 'refractory', 'noise'];

class Detector
{
    public array $peaks;
    public array $initial;
    public array $levels;
    public array $parameters;
    public int $length;
    public array $registered = [];
    public ?Peak $last = null;
    public array $intervals = [];
    public int $average1 = 200;
    public int $average2 = 200;

    public function __construct(array $signals, array $parameters)
    {
        $this->peaks = findPeaks($signals);
        $this->initial = initialLevels($signals);
        $this->levels = $this->initial;
        $this->parameters = $parameters;
        $this->length = count($signals['ecg']);
    }

    public function thresholds(): array
    {
        return [
            'integrated' => $this->levels['npki'] + floorDiv($this->levels['spki'] - $this->levels['npki'], 4),
            'bandpass' => $this->levels['npkf'] + floorDiv($this->levels['spkf'] - $this->levels['npkf'], 4),
        ];
    }

    public function update(Peak $peak, string $kind): void
    {
        $signal = $kind !== 'noise';
        $divisor = $kind === 'searchback' ? 4 : 8;
        $i = $signal ? 'spki' : 'npki';
        $f = $signal ? 'spkf' : 'npkf';
        $this->levels[$i] = floorDiv($peak->peakI + ($divisor - 1) * $this->levels[$i], $divisor);
        $this->levels[$f] = floorDiv($peak->peakF + ($divisor - 1) * $this->levels[$f], $divisor);
    }

    public function register(Peak $peak): void
    {
        if ($this->last !== null) {
            $interval = $peak->time - $this->last->time;
            $this->intervals[] = $interval;
            if (count($this->intervals) > 8) {
                array_shift($this->intervals);
            }
            $this->average1 = intdiv(array_sum($this->intervals), count($this->intervals));
            if (92 * $this->average1 <= 100 * $interval && 100 * $interval <= 116 * $this->average1) {
                $this->average2 = $this->average1;
            }
        }
        $this->last = $peak;
        $this->registered[] = $peak;
    }

    public function searchBack(int $time): void
    {
        while (true) {
            $previous = $this->last?->time ?? 0;
            if ($time - $previous <= intdiv($this->average2 * $this->parameters['searchback_percent'], 100)) {
                return;
            }
            $thresholds = $this->thresholds();
            $lowI = floorDiv($thresholds['integrated'], 2);
            $lowF = floorDiv($thresholds['bandpass'], 2);
            $selected = null;
            foreach ($this->peaks as $peak) {
                if ($peak->kind !== 'noise' || $peak->time <= $previous || $peak->time >= $time || $peak->peakI <= $lowI || $peak->peakF <= $lowF) {
                    continue;
                }
                if ($selected === null || $peak->peakI > $selected->peakI) {
                    $selected = $peak;
                }
            }
            if ($selected === null) {
                return;
            }
            $this->update($selected, 'searchback');
            $selected->kind = 'searchback';
            $this->register($selected);
        }
    }

    public function run(): void
    {
        $refractory = intdiv($this->parameters['refractory_ms'], 5);
        $twave = intdiv($this->parameters['twave_ms'], 5);
        foreach ($this->peaks as $peak) {
            $this->searchBack($peak->time);
            $thresholds = $this->thresholds();
            $peak->thresholdI = $thresholds['integrated'];
            $peak->thresholdF = $thresholds['bandpass'];
            if ($this->last !== null && $peak->time - $this->last->time < $refractory) {
                $peak->kind = 'refractory';
            } elseif ($peak->peakI > $peak->thresholdI && $peak->peakF > $peak->thresholdF) {
                if ($this->last !== null && $peak->time - $this->last->time < $twave && 2 * $peak->slope < $this->last->slope) {
                    $peak->kind = 'twave';
                    $this->update($peak, 'noise');
                } else {
                    $peak->kind = 'qrs';
                    $this->update($peak, 'signal');
                    $this->register($peak);
                }
            } else {
                $peak->kind = 'noise';
                $this->update($peak, 'noise');
            }
        }
        $this->searchBack($this->length);
    }
}

class Beat
{
    public int $number;
    public int $sample;
    public ?int $rr;
    public int $width;
    public string $label = 'N';
    public string $method;
    public ?Annotation $reference = null;
    public ?int $previousTotal = null;
    public bool $nn = false;

    public function __construct(int $number, int $sample, ?int $rr, int $width, string $method)
    {
        $this->number = $number;
        $this->sample = $sample;
        $this->rr = $rr;
        $this->width = $width;
        $this->method = $method;
    }
}

function describeBeats(Detector $detector, array $signals, array $parameters): array
{
    $beats = [];
    foreach ($detector->registered as $peak) {
        $sample = max(0, $peak->position - 21);
        $previous = count($beats) ? $beats[count($beats) - 1] : null;
        $rr = $previous !== null ? 5 * ($sample - $previous->sample) : null;
        $beat = new Beat(count($beats) + 1, $sample, $rr, qrsWidth($signals['bandpass'], $peak->position), $peak->kind === 'qrs' ? 'threshold' : 'searchback');
        if ($beat->number >= 10) {
            $beat->previousTotal = array_sum(array_map(fn($item) => $item->rr, array_slice($beats, -8)));
            if (800 * $rr < $parameters['premature_percent'] * $beat->previousTotal) {
                $beat->label = $beat->width > $parameters['qrs_width_ms'] ? 'V' : 'A';
            }
        }
        if ($beat->number >= 3 && $previous->label === 'N' && $beat->label === 'N' && 5 * abs($rr - $previous->rr) <= $previous->rr) {
            $beat->nn = true;
        }
        $beats[] = $beat;
    }
    return $beats;
}

function matchBeats(array $beats, array $annotations, int $tolerance): void
{
    foreach ($beats as $beat) {
        $selected = null;
        $distance = $tolerance + 1;
        foreach ($annotations as $annotation) {
            if ($annotation->beat !== null) {
                continue;
            }
            $candidate = abs($annotation->sample - $beat->sample);
            if ($candidate <= $tolerance && $candidate < $distance) {
                $selected = $annotation;
                $distance = $candidate;
            }
        }
        if ($selected !== null) {
            $selected->beat = $beat;
            $beat->reference = $selected;
        }
    }
}

function makeSegments(int $length, array $parameters, array $beats, array $annotations, array $peaks): array
{
    $size = intdiv($parameters['segment_ms'], 5);
    $segments = [];
    for ($start = 0; $start < $length; $start += $size) {
        $end = min($start + $size, $length);
        $segments[] = [
            'start' => 5 * $start,
            'end' => 5 * $end,
            'beats' => array_values(array_filter($beats, fn($beat) => $start <= $beat->sample && $beat->sample < $end)),
            'annotations' => array_values(array_filter($annotations, fn($annotation) => $start <= $annotation->sample && $annotation->sample < $end)),
            'peaks' => array_values(array_filter($peaks, fn($peak) => $start <= $peak->time && $peak->time < $end)),
        ];
    }
    return $segments;
}

function pad($value, int $width): string
{
    return str_pad((string) $value, $width, ' ', STR_PAD_LEFT);
}

function numberOrNone(?int $value): string
{
    return $value === null ? 'none' : decimal2($value);
}

function beatLines(array $beats): array
{
    $lines = ['beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label'];
    foreach ($beats as $beat) {
        $lines[] = implode(',', [$beat->number, $beat->sample, 5 * $beat->sample, missing($beat->rr), $beat->rr === null ? '-' : decimal2(rdiv(6000000, $beat->rr)), $beat->width, $beat->label, $beat->method, missing($beat->reference?->sample), missing($beat->reference?->label)]);
    }
    return $lines;
}

function peakLines(array $peaks): array
{
    $lines = ['peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class'];
    foreach ($peaks as $peak) {
        $lines[] = implode(',', [$peak->number, $peak->time, $peak->position, $peak->peakI, $peak->peakF, $peak->slope, $peak->thresholdI, $peak->thresholdF, $peak->kind]);
    }
    return $lines;
}

function matchingLines(array $beats, array $annotations): array
{
    $entries = [];
    foreach ($annotations as $annotation) {
        $beat = $annotation->beat;
        $line = $beat === null
            ? "{$annotation->sample},{$annotation->label},-,-,-,-,FN,-"
            : implode(',', [$annotation->sample, $annotation->label, $beat->number, $beat->sample, $beat->label, 5 * ($beat->sample - $annotation->sample), 'TP', $beat->label === $annotation->label ? 'yes' : 'no']);
        $entries[] = ['sample' => $annotation->sample, 'order' => 0, 'line' => $line];
    }
    foreach ($beats as $beat) {
        if ($beat->reference === null) {
            $entries[] = ['sample' => $beat->sample, 'order' => 1, 'line' => "-,-,{$beat->number},{$beat->sample},{$beat->label},-,FP,-"];
        }
    }
    usort($entries, fn($a, $b) => ($a['sample'] <=> $b['sample']) ?: ($a['order'] <=> $b['order']));
    return array_merge(['ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree'], array_column($entries, 'line'));
}

function signalLines(array $signals, array $parameters): array
{
    $names = ['ecg', 'lowpass', 'bandpass', 'derivative', 'squared', 'integrated'];
    $lines = ['sample,' . implode(',', $names)];
    for ($sample = 0; $sample < intdiv($parameters['excerpt_ms'], 5); $sample++) {
        $values = [$sample];
        foreach ($names as $name) {
            $values[] = $signals[$name][$sample];
        }
        $lines[] = implode(',', $values);
    }
    return $lines;
}

function performanceLines(Detector $detector, array $beats, array $annotations, array $segments): array
{
    $parameters = $detector->parameters;
    $peaks = $detector->peaks;
    $matched = array_values(array_filter($beats, fn($beat) => $beat->reference !== null));
    $extra = array_values(array_filter($beats, fn($beat) => $beat->reference === null));
    $missed = array_values(array_filter($annotations, fn($annotation) => $annotation->beat === null));
    $thresholds = $detector->thresholds();
    $levels = function ($values) {
        $parts = [];
        foreach (['spki', 'npki', 'spkf', 'npkf'] as $name) {
            $parts[] = $name . '=' . $values[$name];
        }
        return implode(' ', $parts);
    };
    $counts = function ($values) {
        $parts = [];
        foreach (LABELS as $label) {
            $parts[] = $label . '=' . count(array_filter($values, fn($value) => $value->label === $label));
        }
        return implode(' ', $parts);
    };
    $peakCounts = [];
    foreach (CLASSES as $kind) {
        $peakCounts[] = $kind . '=' . count(array_filter($peaks, fn($peak) => $peak->kind === $kind));
    }
    $lines = [
        'DETECTOR',
        'samples ' . $detector->length,
        'duration_ms ' . 5 * $detector->length,
        'peaks ' . count($peaks) . ' ' . implode(' ', $peakCounts),
        'initial_levels ' . $levels($detector->initial),
        'final_levels ' . $levels($detector->levels),
        'final_thresholds thr_i=' . $thresholds['integrated'] . ' thr_f=' . $thresholds['bandpass'],
        'final_rr_averages rravg1_ms=' . 5 * $detector->average1 . ' rravg2_ms=' . 5 * $detector->average2,
        'MATCHING',
        'tolerance_ms ' . $parameters['match_ms'],
        'references ' . count($annotations) . ' ' . $counts($annotations),
        'detections ' . count($beats) . ' ' . $counts($beats),
        'true_positives ' . count($matched),
        'false_positives ' . count($extra),
        'false_negatives ' . count($missed),
        'sensitivity ' . ratio(count($matched), count($annotations)),
        'positive_predictivity ' . ratio(count($matched), count($beats)),
        'detection_error_rate ' . ratio(count($extra) + count($missed), count($annotations)),
    ];
    $methods = [];
    foreach (['threshold', 'searchback'] as $method) {
        $methods[] = $method . '=' . count(array_filter($matched, fn($beat) => $beat->method === $method)) . '/' . count(array_filter($beats, fn($beat) => $beat->method === $method));
    }
    $lines[] = 'by_method ' . implode(' ', $methods);
    if (count($matched)) {
        $offsets = array_map(fn($beat) => 5 * ($beat->sample - $beat->reference->sample), $matched);
        $absolute = array_map('abs', $offsets);
        $lines[] = 'offset_ms mean=' . decimal2(rdiv(100 * array_sum($offsets), count($offsets)))
            . ' mean_abs=' . decimal2(rdiv(100 * array_sum($absolute), count($absolute))) . ' max_abs=' . max($absolute);
    } else {
        $lines[] = 'offset_ms none';
    }
    $lines[] = 'CONFUSION';
    $lines[] = 'ref  ' . implode('', array_map(fn($label) => pad($label, 6), LABELS)) . '  miss';
    foreach (LABELS as $label) {
        $line = $label . '    ';
        foreach (LABELS as $predicted) {
            $line .= pad(count(array_filter($matched, fn($beat) => $beat->reference->label === $label && $beat->label === $predicted)), 6);
        }
        $line .= pad(count(array_filter($missed, fn($annotation) => $annotation->label === $label)), 6);
        $lines[] = $line;
    }
    $line = 'extra';
    foreach (LABELS as $label) {
        $line .= pad(count(array_filter($extra, fn($beat) => $beat->label === $label)), 6);
    }
    $lines[] = $line;
    foreach ([['V', 'veb'], ['A', 'sveb']] as [$label, $name]) {
        $hits = count(array_filter($matched, fn($beat) => $beat->label === $label && $beat->reference->label === $label));
        $lines[] = $name . '_sensitivity ' . ratio($hits, count(array_filter($annotations, fn($annotation) => $annotation->label === $label)));
        $lines[] = $name . '_positive_predictivity ' . ratio($hits, count(array_filter($beats, fn($beat) => $beat->label === $label)));
    }
    $lines[] = 'SEGMENTS segment_ms=' . $parameters['segment_ms'] . ' segments=' . count($segments);
    foreach ($segments as $segment) {
        $tp = count(array_filter($segment['annotations'], fn($annotation) => $annotation->beat !== null));
        $fp = count(array_filter($segment['beats'], fn($beat) => $beat->reference === null));
        $noise = count(array_filter($segment['peaks'], fn($peak) => $peak->kind === 'noise'));
        $lines[] = pad($segment['start'], 6) . '-' . pad($segment['end'], 6) . ' refs=' . count($segment['annotations']) . ' tp=' . $tp . ' fp=' . $fp . ' fn=' . (count($segment['annotations']) - $tp) . ' noise_peaks=' . $noise;
    }
    $lines[] = 'ERRORS count=' . (count($extra) + count($missed));
    $errors = [];
    foreach ($extra as $beat) {
        $errors[] = ['sample' => $beat->sample, 'order' => 0, 'line' => 'false_positive beat=' . $beat->number . ' sample=' . $beat->sample . ' time_ms=' . 5 * $beat->sample . ' label=' . $beat->label];
    }
    foreach ($missed as $annotation) {
        $errors[] = ['sample' => $annotation->sample, 'order' => 1, 'line' => 'false_negative sample=' . $annotation->sample . ' time_ms=' . 5 * $annotation->sample . ' label=' . $annotation->label];
    }
    usort($errors, fn($a, $b) => ($a['sample'] <=> $b['sample']) ?: ($a['order'] <=> $b['order']));
    return array_merge($lines, array_column($errors, 'line'));
}

function runLines(array $beats): array
{
    $runs = [];
    foreach (['V', 'A'] as $label) {
        foreach (ranges($beats, fn($beat) => $beat->label === $label) as [$start, $end]) {
            $length = $end - $start + 1;
            $kind = $length === 1 ? 'isolated' : ($length === 2 ? 'couplet' : 'run');
            $runs[] = ['start' => $start, 'line' => $label . ' ' . $kind . ' beats=' . $beats[$start]->number . '-' . $beats[$end]->number . ' length=' . $length . ' start_ms=' . 5 * $beats[$start]->sample];
        }
    }
    usort($runs, fn($a, $b) => $a['start'] <=> $b['start']);
    return array_column($runs, 'line');
}

function eventLines(array $beats, array $parameters): array
{
    $lines = [];
    for ($i = 1; $i < count($beats); $i++) {
        if ($beats[$i]->rr > $parameters['pause_ms']) {
            $lines[] = 'pause beats=' . $beats[$i - 1]->number . '-' . $beats[$i]->number . ' rr_ms=' . $beats[$i]->rr . ' start_ms=' . 5 * $beats[$i - 1]->sample;
        }
    }
    $criteria = [
        ['bradycardia', fn($beat) => $beat->rr !== null && $beat->rr > $parameters['brady_ms']],
        ['tachycardia', fn($beat) => $beat->rr !== null && $beat->rr < $parameters['tachy_ms']],
    ];
    foreach ($criteria as [$kind, $predicate]) {
        foreach (ranges($beats, $predicate) as [$start, $end]) {
            $count = $end - $start + 1;
            if ($count < 3) {
                continue;
            }
            $intervals = array_map(fn($beat) => $beat->rr, array_slice($beats, $start, $count));
            $lines[] = $kind . ' beats=' . $beats[$start - 1]->number . '-' . $beats[$end]->number . ' intervals=' . $count . ' mean_hr=' . decimal2(meanHeartRate($intervals)) . ' start_ms=' . 5 * $beats[$start - 1]->sample;
        }
    }
    $ventricular = [];
    foreach ($beats as $index => $beat) {
        if ($beat->label === 'V') {
            $ventricular[] = $index;
        }
    }
    foreach ([['bigeminy', 2], ['trigeminy', 3]] as [$kind, $spacing]) {
        $sequence = [];
        $finish = function () use (&$sequence, &$lines, $beats, $kind) {
            if (count($sequence) >= 3) {
                $first = $sequence[0];
                $last = $sequence[count($sequence) - 1];
                $lines[] = $kind . ' beats=' . $beats[$first]->number . '-' . $beats[$last]->number . ' cycles=' . count($sequence) . ' start_ms=' . 5 * $beats[$first]->sample;
            }
        };
        foreach ($ventricular as $index) {
            $linked = count($sequence) > 0 && $index === $sequence[count($sequence) - 1] + $spacing;
            if ($linked) {
                for ($i = $sequence[count($sequence) - 1] + 1; $i < $index; $i++) {
                    if ($beats[$i]->label !== 'N') {
                        $linked = false;
                        break;
                    }
                }
            }
            if (!$linked) {
                $finish();
                $sequence = [];
            }
            $sequence[] = $index;
        }
        $finish();
    }
    return $lines;
}

function hrvLines(array $beats, array $segments, array $parameters): array
{
    $rr = array_map(fn($beat) => $beat->rr, array_slice($beats, 1));
    $nn = [];
    $pairs = [];
    foreach ($beats as $i => $beat) {
        if ($beat->nn) {
            $nn[] = $beat->rr;
        }
        if ($i > 0 && $beats[$i - 1]->nn && $beat->nn) {
            $pairs[] = [$beats[$i - 1]->rr, $beat->rr];
        }
    }
    $stats = intervalStatistics($rr, $nn, $pairs);
    $lines = ['RR', 'beats ' . count($beats), 'intervals ' . count($rr), 'mean_rr_ms ' . numberOrNone($stats['meanRR'])];
    if (count($rr)) {
        $shortest = $beats[1];
        $longest = $beats[1];
        foreach (array_slice($beats, 2) as $beat) {
            if ($beat->rr < $shortest->rr) {
                $shortest = $beat;
            }
            if ($beat->rr > $longest->rr) {
                $longest = $beat;
            }
        }
        $lines[] = 'min_rr_ms ' . $shortest->rr . ' beat=' . $shortest->number;
        $lines[] = 'max_rr_ms ' . $longest->rr . ' beat=' . $longest->number;
    } else {
        $lines[] = 'min_rr_ms none';
        $lines[] = 'max_rr_ms none';
    }
    $lines[] = 'mean_hr_bpm ' . numberOrNone($stats['meanHR']);
    $lines[] = 'NN';
    $lines[] = 'intervals ' . count($nn);
    $lines[] = 'mean_nn_ms ' . numberOrNone($stats['meanNN']);
    $lines[] = 'sdnn_ms ' . numberOrNone($stats['sdnn']);
    $lines[] = 'differences ' . count($pairs);
    $lines[] = 'rmssd_ms ' . numberOrNone($stats['rmssd']);
    $lines[] = 'sdsd_ms ' . numberOrNone($stats['sdsd']);
    $lines[] = 'nn50 ' . $stats['nn50'];
    $lines[] = 'pnn50 ' . ($stats['pnn50'] === null ? 'none' : decimal2($stats['pnn50']) . '%');
    $lines[] = 'sd1_ms ' . numberOrNone($stats['sd1']);
    $lines[] = 'sd2_ms ' . numberOrNone($stats['sd2']);
    $bins = histogram($nn);
    $maximum = count($bins) ? max($bins) : 0;
    $lines[] = 'HISTOGRAM bin_ms=7.8125 bins=' . count($bins) . ' max=' . $maximum;
    foreach ($bins as $bin => $count) {
        $lines[] = pad(decimal4(78125 * $bin), 10) . ' ' . pad(decimal4(78125 * ($bin + 1)), 10) . ' ' . pad($count, 3) . ' |' . str_repeat('#', $count);
    }
    $lines[] = 'triangular_index ' . (count($nn) ? fraction(count($nn), $maximum) . ' ' . decimal2(rdiv(100 * count($nn), $maximum)) : 'none');
    $premature = array_values(array_filter($beats, fn($beat) => $beat->label !== 'N'));
    $vCount = count(array_filter($premature, fn($beat) => $beat->label === 'V'));
    $aCount = count(array_filter($premature, fn($beat) => $beat->label === 'A'));
    $lines[] = 'PREMATURE count=' . count($premature) . ' V=' . $vCount . ' A=' . $aCount;
    foreach ($premature as $beat) {
        $next = $beats[$beat->number] ?? null;
        $total = $beat->previousTotal;
        $compensation = '-';
        if ($next !== null) {
            $pair = $beat->rr + $next->rr;
            $compensation = 10 * abs(4 * $pair - $total) <= $total ? 'full' : (4 * $pair < $total ? 'partial' : 'long');
        }
        $lines[] = 'beat=' . $beat->number . ' sample=' . $beat->sample . ' label=' . $beat->label . ' rr_ms=' . $beat->rr
            . ' next_rr_ms=' . missing($next?->rr) . ' mean_ms=' . decimal2(rdiv(100 * $total, 8))
            . ' prematurity=' . decimal2(rdiv(80000 * $beat->rr, $total)) . '% compensation=' . $compensation
            . ' width_ms=' . $beat->width . ' ref=' . missing($beat->reference?->label);
    }
    $runs = runLines($beats);
    $lines[] = 'RUNS count=' . count($runs);
    $lines = array_merge($lines, $runs);
    $events = eventLines($beats, $parameters);
    $lines[] = 'EVENTS count=' . count($events);
    $lines = array_merge($lines, $events);
    $lines[] = 'TREND segment_ms=' . $parameters['segment_ms'] . ' segments=' . count($segments);
    foreach ($segments as $segment) {
        $intervals = [];
        foreach ($segment['beats'] as $beat) {
            if ($beat->rr !== null) {
                $intervals[] = $beat->rr;
            }
        }
        $prefix = pad($segment['start'], 6) . '-' . pad($segment['end'], 6) . ' beats=' . count($segment['beats']);
        if (count($intervals)) {
            $mean = meanHeartRate($intervals);
            $lines[] = $prefix . ' mean_hr=' . decimal2($mean) . ' min_hr=' . decimal2(rdiv(6000000, max($intervals)))
                . ' max_hr=' . decimal2(rdiv(6000000, min($intervals))) . ' |' . str_repeat('#', rdiv($mean, 500));
        } else {
            $lines[] = $prefix . ' mean_hr=none min_hr=none max_hr=none |';
        }
    }
    return $lines;
}

function scale(int $value, int $top, int $bottom, int $height): int
{
    return $top > $bottom ? rdiv(($top - $value) * ($height - 1), $top - $bottom) : 0;
}

function waveform(array $highs, array $lows, int $height): array
{
    $top = max($highs);
    $bottom = min($lows);
    $zero = $bottom <= 0 && $top >= 0 ? scale(0, $top, $bottom, $height) : null;
    $highRows = array_map(fn($value) => scale($value, $top, $bottom, $height), $highs);
    $lowRows = array_map(fn($value) => scale($value, $top, $bottom, $height), $lows);
    $lines = [];
    for ($row = 0; $row < $height; $row++) {
        $label = $row === 0 ? $top : ($row === $height - 1 ? $bottom : ($row === $zero ? 0 : ''));
        $cells = '';
        foreach ($highRows as $column => $high) {
            $cells .= $high <= $row && $row <= $lowRows[$column] ? '#' : ($row === $zero ? '-' : ' ');
        }
        $lines[] = pad($label, 6) . ' |' . $cells . '|';
    }
    return $lines;
}

function axisRow(int $width, callable $marked): string
{
    $line = '       +';
    for ($column = 0; $column < $width; $column++) {
        $line .= $marked($column) ? '+' : '-';
    }
    return $line . '+';
}

function labelRow(string $heading, array $labels): string
{
    $line = pad($heading, 6);
    foreach ($labels as [$column, $value]) {
        $line = str_pad($line, 8 + $column, ' ') . $value;
    }
    return $line;
}

function intervalCharts(array $beats, array $parameters): array
{
    $rr = array_map(fn($beat) => $beat->rr, array_slice($beats, 1));
    if (count($rr) === 0) {
        return ['TACHOGRAM intervals=0', 'POINCARE points=0'];
    }
    $low = min($rr);
    $high = max($rr);
    $height = $parameters['chart_rows'];
    $lines = ['TACHOGRAM intervals=' . count($rr) . ' min_ms=' . $low . ' max_ms=' . $high . ' rows=' . $height];
    $scaled = array_map(fn($value) => scale($value, $high, $low, $height), $rr);
    for ($row = 0; $row < $height; $row++) {
        $label = $row === 0 ? $high : ($row === $height - 1 ? $low : '');
        $cells = '';
        foreach ($scaled as $position) {
            $cells .= $position === $row ? '*' : ' ';
        }
        $lines[] = pad($label, 6) . ' |' . $cells . '|';
    }
    $labels = [];
    for ($column = 0; $column < count($rr); $column++) {
        if (($column + 2) % 10 === 0) {
            $labels[] = [$column, $column + 2];
        }
    }
    $lines[] = axisRow(count($rr), fn($column) => ($column + 2) % 10 === 0);
    $lines[] = labelRow('beat', $labels);
    $lines[] = ' label |' . implode('', array_map(fn($beat) => $beat->label, array_slice($beats, 1))) . '|';
    $size = $parameters['poincare_size'];
    $cells = array_fill(0, $size, array_fill(0, $size, 0));
    for ($i = 0; $i + 1 < count($rr); $i++) {
        $column = $high > $low ? rdiv(($rr[$i] - $low) * ($size - 1), $high - $low) : 0;
        $row = scale($rr[$i + 1], $high, $low, $size);
        $cells[$row][$column]++;
    }
    $lines[] = 'POINCARE points=' . (count($beats) - 2) . ' size=' . $size . ' min_ms=' . $low . ' max_ms=' . $high;
    for ($row = 0; $row < $size; $row++) {
        $label = $row === 0 ? $high : ($row === $size - 1 ? $low : '');
        $characters = '';
        foreach ($cells[$row] as $count) {
            $characters .= $count === 0 ? '.' : ($count <= 9 ? (string) $count : '#');
        }
        $lines[] = pad($label, 6) . ' |' . $characters . '|';
    }
    $lines[] = '       +' . str_repeat('-', $size) . '+';
    $lines[] = str_pad('        ' . $low, 8 + $size - strlen((string) $high), ' ') . $high;
    return $lines;
}

function templateCharts(array $ecg, array $beats, array $parameters): array
{
    $lines = [];
    foreach (LABELS as $label) {
        $selected = array_values(array_filter($beats, fn($beat) => $beat->label === $label && $beat->sample >= 60 && $beat->sample <= count($ecg) - 100));
        if (count($selected) === 0) {
            $lines[] = 'TEMPLATE ' . $label . ' beats=0';
            continue;
        }
        $baselines = [];
        foreach ($selected as $beat) {
            $baselines[] = array_sum(array_slice($ecg, $beat->sample - 60, 10));
        }
        $values = [];
        for ($index = 0; $index < 160; $index++) {
            $total = 0;
            foreach ($selected as $k => $beat) {
                $total += 10 * $ecg[$beat->sample + $index - 60] - $baselines[$k];
            }
            $values[] = rdiv($total, 10 * count($selected));
        }
        $top = max($values);
        $bottom = min($values);
        $highs = [];
        $lows = [];
        for ($i = 0; $i < 160; $i += 2) {
            $highs[] = max($values[$i], $values[$i + 1]);
            $lows[] = min($values[$i], $values[$i + 1]);
        }
        $lines[] = 'TEMPLATE ' . $label . ' beats=' . count($selected) . ' max_uv=' . $top
            . ' max_ms=' . 5 * (array_search($top, $values, true) - 60) . ' min_uv=' . $bottom
            . ' min_ms=' . 5 * (array_search($bottom, $values, true) - 60) . ' rows=' . $parameters['chart_rows'];
        $lines = array_merge($lines, waveform($highs, $lows, $parameters['chart_rows']));
        $lines[] = axisRow(80, fn($column) => $column % 10 === 0);
        $labels = [];
        for ($i = 0; $i < 8; $i++) {
            $labels[] = [10 * $i, 100 * $i - 300];
        }
        $lines[] = labelRow('ms', $labels);
    }
    return $lines;
}

function rhythmLines(array $ecg, array $beats, array $annotations, array $parameters): array
{
    $start = intdiv($parameters['strip_start_ms'], 5);
    $length = intdiv($parameters['strip_ms'], 5);
    $width = intdiv($length, 10);
    $highs = [];
    $lows = [];
    for ($column = 0; $column < $width; $column++) {
        $values = array_slice($ecg, $start + 10 * $column, 10);
        $highs[] = max($values);
        $lows[] = min($values);
    }
    $labels = [];
    for ($column = 0; $column < $width; $column += 20) {
        $labels[] = [$column, intdiv($parameters['strip_start_ms'] + 50 * $column, 1000)];
    }
    $beatMarks = array_fill(0, $width, ' ');
    $referenceMarks = array_fill(0, $width, ' ');
    foreach ($beats as $beat) {
        if ($start <= $beat->sample && $beat->sample < $start + $length) {
            $beatMarks[intdiv($beat->sample - $start, 10)] = $beat->label;
        }
    }
    foreach ($annotations as $annotation) {
        if ($start <= $annotation->sample && $annotation->sample < $start + $length) {
            $referenceMarks[intdiv($annotation->sample - $start, 10)] = $annotation->label;
        }
    }
    $lines = ['RHYTHM start_ms=' . $parameters['strip_start_ms'] . ' end_ms=' . ($parameters['strip_start_ms'] + $parameters['strip_ms'])
        . ' columns=' . $width . ' rows=' . $parameters['strip_rows'] . ' max_uv=' . max($highs) . ' min_uv=' . min($lows)];
    $lines = array_merge($lines, waveform($highs, $lows, $parameters['strip_rows']));
    $lines[] = axisRow($width, fn($column) => $column % 20 === 0);
    $lines[] = labelRow('s', $labels);
    $lines[] = ' beats |' . implode('', $beatMarks) . '|';
    $lines[] = '  refs |' . implode('', $referenceMarks) . '|';
    return $lines;
}

function main(): void
{
    [$ecg, $annotations, $parameters] = readInput();
    $signals = filterSignal($ecg);
    $detector = new Detector($signals, $parameters);
    $detector->run();
    $beats = describeBeats($detector, $signals, $parameters);
    matchBeats($beats, $annotations, intdiv($parameters['match_ms'], 5));
    $segments = makeSegments(count($ecg), $parameters, $beats, $annotations, $detector->peaks);
    $outputs = [
        'beats.csv' => beatLines($beats),
        'peaks.csv' => peakLines($detector->peaks),
        'matching.csv' => matchingLines($beats, $annotations),
        'signals_excerpt.csv' => signalLines($signals, $parameters),
        'performance.txt' => performanceLines($detector, $beats, $annotations, $segments),
        'hrv.txt' => hrvLines($beats, $segments, $parameters),
        'charts.txt' => array_merge(intervalCharts($beats, $parameters), templateCharts($ecg, $beats, $parameters)),
        'rhythm_strip.txt' => rhythmLines($ecg, $beats, $annotations, $parameters),
    ];
    foreach ($outputs as $name => $lines) {
        writeLines($name, $lines);
    }
}

main();
