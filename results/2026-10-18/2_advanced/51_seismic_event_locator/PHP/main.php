<?php

require_once __DIR__ . '/waveform_io.php';
require_once __DIR__ . '/magnitude.php';
require_once __DIR__ . '/picker.php';
require_once __DIR__ . '/associator.php';
require_once __DIR__ . '/locator.php';

function sumValues(array $values): float
{
    $sum = 0.0;
    foreach ($values as $value) {
        $sum += $value;
    }
    return $sum;
}

function fixed(?float $value, int $digits): string
{
    if ($value === null) {
        return '-';
    }
    $text = number_format(abs($value), $digits, '.', '');
    return $value < 0 && (float) $text !== 0.0 ? '-' . $text : $text;
}

function scaled(float $value, int $digits): int
{
    return (int) str_replace('.', '', fixed($value, $digits));
}

function floorQuotient(int|float $numerator, int|float $denominator): int
{
    if (!is_int($numerator) || !is_int($denominator)) {
        return (int) floor($numerator / $denominator);
    }
    $quotient = intdiv($numerator, $denominator);
    return $numerator < 0 && $numerator % $denominator !== 0 ? $quotient - 1 : $quotient;
}

function timeNotation(int $sample): string
{
    return intdiv($sample, 100) . '.' . str_pad((string) ($sample % 100), 2, '0', STR_PAD_LEFT);
}

function classNotation(int $value): string
{
    return ($value < 0 ? '-' : '') . intdiv(abs($value), 10) . '.' . (abs($value) % 10);
}

function rms(array $values): ?float
{
    if (!$values) {
        return null;
    }
    $squares = 0.0;
    foreach ($values as $value) {
        $squares += $value * $value;
    }
    return sqrt($squares / count($values));
}

function observation(object $pick): object
{
    return (object) ['station' => $pick->station, 'time' => $pick->time, 'pick' => $pick];
}

function processCandidates(array $candidates, object $params): array
{
    $events = [];
    foreach ($candidates as $candidate) {
        usort($candidate->picks, fn($a, $b) => $a->station->index <=> $b->station->index);
        $candidate->pass1 = locationRun(array_map('observation', $candidate->picks), $params);
        $candidate->dropped = [];
        $candidate->remaining = [];
        foreach ($candidate->picks as $i => $pick) {
            if (abs($candidate->pass1->residuals[$i]) > $params->residualLimit) {
                $candidate->dropped[] = (object) ['pick' => $pick, 'residual' => $candidate->pass1->residuals[$i]];
            } else {
                $candidate->remaining[] = $pick;
            }
        }
        $candidate->rejected = count($candidate->dropped) > 0 && count($candidate->remaining) < $params->minStations;
        if ($candidate->rejected) {
            foreach ($candidate->picks as $pick) {
                $pick->state = 'rejected';
            }
            continue;
        }
        $candidate->pass2 = $candidate->dropped ? locationRun(array_map('observation', $candidate->remaining), $params) : null;
        $adopted = $candidate->pass2 ?? $candidate->pass1;
        $event = (object) ['number' => count($events) + 1, 'used' => $candidate->remaining, 'firstStage' => $adopted];
        $candidate->event = $event;
        foreach ($event->used as $i => $pick) {
            $pick->state = 'used';
            $pick->event = $event->number;
            $pick->firstResidual = $adopted->residuals[$i];
            $pick->station->used[] = $pick;
        }
        foreach ($candidate->dropped as $item) {
            $item->pick->state = 'dropped';
            $item->pick->event = $event->number;
        }
        $events[] = $event;
    }
    return $events;
}

function qualityAndStability(object $event, object $params): void
{
    $point = $event->relocation->point;
    $event->ellipse = uncertainty($point, $event->corrected, $params->velocity);
    $dx = $point->x - $event->firstStage->point->x;
    $dy = $point->y - $event->firstStage->point->y;
    $event->shift = (object) ['dh' => sqrt($dx * $dx + $dy * $dy), 'dz' => $point->z - $event->firstStage->point->z];
    $azimuths = [];
    $horizontal = [];
    foreach ($event->used as $pick) {
        $sx = $pick->station->x - $point->x;
        $sy = $pick->station->y - $point->y;
        $azimuth = atan2($sx, $sy) * 180 / 3.141592653589793;
        if ($azimuth < 0) {
            $azimuth += 360;
        }
        $azimuths[] = $azimuth;
        $horizontal[] = sqrt($sx * $sx + $sy * $sy);
    }
    sort($azimuths, SORT_NUMERIC);
    $event->gap = $azimuths[0] + 360 - $azimuths[count($azimuths) - 1];
    for ($i = 1; $i < count($azimuths); $i++) {
        $event->gap = max($event->gap, $azimuths[$i] - $azimuths[$i - 1]);
    }
    $event->dmin = min($horizontal);
    $meets = fn($limits) => $event->gap <= $limits[0] && $event->relocation->rms <= $limits[1] && $event->ellipse->smaj <= $limits[2];
    $event->quality = $meets($params->qualityA) ? 'A' : ($meets($params->qualityB) ? 'B' : 'C');
    $event->jackknife = [];
    foreach ($event->used as $removed => $pick) {
        $observations = $event->corrected;
        array_splice($observations, $removed, 1);
        $result = geiger($point, $observations, $params->velocity)->point;
        $dx = $result->x - $point->x;
        $dy = $result->y - $point->y;
        $event->jackknife[] = (object) ['station' => $pick->station, 'dx' => $dx, 'dy' => $dy,
            'dz' => $result->z - $point->z, 'shift' => sqrt($dx * $dx + $dy * $dy)];
    }
    $event->worstJackknife = $event->jackknife[0];
    foreach ($event->jackknife as $jack) {
        if ($jack->shift > $event->worstJackknife->shift) {
            $event->worstJackknife = $jack;
        }
    }
}

function relocateEvents(array $stations, array $events, object $params): void
{
    foreach ($stations as $station) {
        $residuals = array_map(fn($pick) => $pick->firstResidual, $station->used);
        $station->correction = $residuals ? sumValues($residuals) / count($residuals) : 0.0;
    }
    foreach ($events as $event) {
        $event->corrected = array_map(fn($pick) => (object) ['station' => $pick->station,
            'time' => $pick->time - $pick->station->correction, 'pick' => $pick], $event->used);
        $event->startRms = evaluate($event->firstStage->point, $event->corrected, $params->velocity)->rms;
        $event->relocation = geiger($event->firstStage->point, $event->corrected, $params->velocity);
        foreach ($event->used as $i => $pick) {
            $pick->residual = $event->relocation->residuals[$i];
        }
        qualityAndStability($event, $params);
    }
}

function computeMagnitudes(array $stations, array $events, object $params): void
{
    foreach ($events as $event) {
        $event->unclipped = [];
        foreach ($event->used as $i => $pick) {
            $pick->distanceKm = $event->relocation->distances[$i] / 1000;
            $pick->ml = $pick->clipped ? null : localMagnitude($pick->amplitude, $pick->distanceKm, $params->localMagnitude);
            $pick->md = durationMagnitude($pick->duration, $pick->distanceKm, $params->durationMagnitude);
            if (!$pick->clipped) {
                $event->unclipped[] = $pick;
            }
        }
        $event->ml = median(array_map(fn($pick) => $pick->ml, $event->unclipped));
        $event->md = median(array_map(fn($pick) => $pick->md, $event->used));
        foreach ($event->unclipped as $pick) {
            $pick->mlResidual = $pick->ml - $event->ml;
        }
        $event->hundredths = $event->ml === null ? null : scaled($event->ml, 2);
        $event->magnitudeClass = $event->ml === null ? null : magnitudeClass($event->hundredths);
    }
    foreach ($stations as $station) {
        $station->magnitudePicks = array_values(array_filter($station->used, fn($pick) => !$pick->clipped));
        $residuals = array_map(fn($pick) => $pick->mlResidual, $station->magnitudePicks);
        $station->magnitudeCorrection = $residuals ? sumValues($residuals) / count($residuals) : 0.0;
    }
    foreach ($events as $event) {
        $event->mlc = median(array_map(fn($pick) => $pick->ml - $pick->station->magnitudeCorrection, $event->unclipped));
    }
}

function travelTimeFit(array $events): object
{
    $points = [];
    $sd = 0.0;
    $st = 0.0;
    $sdd = 0.0;
    $sdt = 0.0;
    foreach ($events as $event) {
        foreach ($event->used as $pick) {
            $d = $pick->distanceKm;
            $t = $pick->time - $event->relocation->point->t0;
            $points[] = [$d, $t];
            $sd += $d;
            $st += $t;
            $sdd += $d * $d;
            $sdt += $d * $t;
        }
    }
    $n = count($points);
    $slope = ($n * $sdt - $sd * $st) / ($n * $sdd - $sd * $sd);
    $intercept = ($st - $slope * $sd) / $n;
    $squares = 0.0;
    foreach ($points as [$d, $t]) {
        $residual = $t - $intercept - $slope * $d;
        $squares += $residual * $residual;
    }
    return (object) ['n' => $n, 'velocity' => 1000 / $slope, 'intercept' => $intercept, 'rms' => sqrt($squares / $n)];
}

function clusterEvents(array $events, object $params): array
{
    [$distanceLimit, $timeLimit] = $params->cluster;
    $count = count($events);
    $neighbors = array_fill(0, $count, []);
    for ($i = 0; $i < $count; $i++) {
        for ($j = $i + 1; $j < $count; $j++) {
            $first = $events[$i]->relocation->point;
            $second = $events[$j]->relocation->point;
            $dx = $first->x - $second->x;
            $dy = $first->y - $second->y;
            $dz = $first->z - $second->z;
            if (abs($first->t0 - $second->t0) <= $timeLimit && sqrt($dx * $dx + $dy * $dy + $dz * $dz) <= $distanceLimit) {
                $neighbors[$i][] = $j;
                $neighbors[$j][] = $i;
            }
        }
    }
    $clusters = [];
    for ($first = 0; $first < $count; $first++) {
        if (isset($events[$first]->cluster)) {
            continue;
        }
        $number = count($clusters) + 1;
        $queue = [$first];
        $events[$first]->cluster = $number;
        for ($position = 0; $position < count($queue); $position++) {
            foreach ($neighbors[$queue[$position]] as $next) {
                if (!isset($events[$next]->cluster)) {
                    $events[$next]->cluster = $number;
                    $queue[] = $next;
                }
            }
        }
        sort($queue, SORT_NUMERIC);
        $members = [];
        $xs = [];
        $ys = [];
        $zs = [];
        $times = [];
        foreach ($queue as $index) {
            $members[] = $events[$index];
            $point = $events[$index]->relocation->point;
            $xs[] = $point->x;
            $ys[] = $point->y;
            $zs[] = $point->z;
            $times[] = $point->t0;
        }
        $size = count($members);
        $clusters[] = (object) ['number' => $number, 'members' => $members, 'x' => sumValues($xs) / $size,
            'y' => sumValues($ys) / $size, 'z' => sumValues($zs) / $size, 'span' => max($times) - min($times)];
    }
    return $clusters;
}

function reassociate(array $picks, array $events, object $params): array
{
    $stationSets = [];
    foreach ($events as $event) {
        $set = [];
        foreach ($event->used as $pick) {
            $set[$pick->station->index] = true;
        }
        $stationSets[] = $set;
    }
    $added = [];
    foreach ($picks as $pick) {
        if ($pick->state !== 'unassociated') {
            continue;
        }
        $best = null;
        foreach ($events as $index => $event) {
            if (isset($stationSets[$index][$pick->station->index])) {
                continue;
            }
            $point = $event->relocation->point;
            $residual = $pick->time - $point->t0 - distance($point, $pick->station) / $params->velocity - $pick->station->correction;
            if (abs($residual) <= $params->residualLimit && ($best === null || abs($residual) < abs($best->residual))) {
                $best = (object) ['index' => $index, 'residual' => $residual];
            }
        }
        if ($best !== null) {
            $pick->state = 'added';
            $pick->event = $events[$best->index]->number;
            $pick->residual = $best->residual;
            $stationSets[$best->index][$pick->station->index] = true;
            $added[] = $pick;
        }
    }
    return $added;
}

function catalogStatistics(array $events): object
{
    $measured = array_values(array_filter($events, fn($event) => $event->ml !== null));
    $frequency = frequencyStatistics(array_map(fn($event) => $event->magnitudeClass, $measured));
    $n = count($measured);
    $xbar = sumValues(array_map(fn($event) => $event->md, $measured)) / $n;
    $ybar = sumValues(array_map(fn($event) => $event->ml, $measured)) / $n;
    $xx = 0.0;
    $xy = 0.0;
    $yy = 0.0;
    foreach ($measured as $event) {
        $x = $event->md - $xbar;
        $y = $event->ml - $ybar;
        $xx += $x * $x;
        $xy += $x * $y;
        $yy += $y * $y;
    }
    $slope = $xy / $xx;
    return (object) ['frequency' => $frequency, 'measured' => $n,
        'relation' => (object) ['n' => $n, 'slope' => $slope, 'intercept' => $ybar - $slope * $xbar,
            'r' => $xy / sqrt($xx * $yy), 'meanDifference' => $ybar - $xbar]];
}

function solutionLine(string $label, object $point, float $residualRms): string
{
    return $label . ' x=' . fixed($point->x, 1) . ' y=' . fixed($point->y, 1) . ' z=' . fixed($point->z, 1)
        . ' t0=' . fixed($point->t0, 3) . ' rms=' . fixed($residualRms, 4);
}

function iterationLines(array $iterations): array
{
    $lines = [];
    foreach ($iterations as $i => $iteration) {
        $lines[] = solutionLine('ITER ' . ($i + 1), $iteration->point, $iteration->rms);
    }
    return $lines;
}

function passLines(object $pass, int $number, float $velocity): array
{
    $codes = array_map(fn($item) => $item->station->code, $pass->observations);
    $profile = array_map(fn($value) => fixed($value, 4), $pass->grid->profile);
    $lines = ['PASS ' . $number . ' stations=' . implode(',', $codes), solutionLine('GRID', $pass->grid->point, $pass->grid->rms),
        'PROFILE ' . implode(' ', $profile)];
    array_push($lines, ...iterationLines($pass->iterations));
    foreach ($pass->observations as $i => $item) {
        $lines[] = 'RES ' . $item->station->code . ' dist=' . fixed($pass->distances[$i], 1)
            . ' tt=' . fixed($pass->distances[$i] / $velocity, 4) . ' obs=' . timeNotation($item->pick->sample)
            . ' res=' . fixed($pass->residuals[$i], 4);
    }
    return $lines;
}

function locationsLines(array $stations, array $picks, array $candidates, array $events, object $fit,
    array $clusters, array $added, object $params): array
{
    $lines = [];
    foreach ($candidates as $candidate) {
        $lines[] = 'CANDIDATE ' . $candidate->number . ' picks=' . count($candidate->picks) . ' first=' . timeNotation($candidate->first->sample);
        array_push($lines, ...passLines($candidate->pass1, 1, $params->velocity));
        foreach ($candidate->dropped as $item) {
            $lines[] = 'DROP ' . $item->pick->station->code . ' res=' . fixed($item->residual, 4);
        }
        if ($candidate->rejected) {
            $lines[] = 'RESULT REJECTED stations=' . count($candidate->remaining);
        } else {
            if ($candidate->pass2 !== null) {
                array_push($lines, ...passLines($candidate->pass2, 2, $params->velocity));
            }
            $lines[] = 'RESULT EVENT ' . $candidate->event->number;
        }
    }
    $lines[] = 'CORRECTIONS';
    foreach ($stations as $station) {
        $lines[] = $station->code . ' n=' . count($station->used) . ' correction=' . fixed($station->correction, 4);
    }
    foreach ($events as $event) {
        $lines[] = 'EVENT ' . $event->number;
        $lines[] = solutionLine('START', $event->firstStage->point, $event->startRms);
        array_push($lines, ...iterationLines($event->relocation->iterations));
        foreach ($event->used as $i => $pick) {
            $length = $event->relocation->distances[$i];
            $lines[] = 'RES ' . $pick->station->code . ' dist=' . fixed($length, 1) . ' tt=' . fixed($length / $params->velocity, 4)
                . ' obs=' . timeNotation($pick->sample) . ' corr=' . fixed($pick->station->correction, 4) . ' res=' . fixed($pick->residual, 4);
        }
        $ellipse = $event->ellipse;
        $lines[] = 'ELLIPSE smaj=' . fixed($ellipse->smaj, 1) . ' smin=' . fixed($ellipse->smin, 1) . ' az=' . fixed($ellipse->az, 1)
            . ' erz=' . fixed($ellipse->erz, 1) . ' ert=' . fixed($ellipse->ert, 4);
        $lines[] = 'SHIFT dh=' . fixed($event->shift->dh, 1) . ' dz=' . fixed($event->shift->dz, 1);
        $lines[] = 'GAP ' . fixed($event->gap, 1) . ' DMIN ' . fixed($event->dmin, 1) . ' QUALITY ' . $event->quality;
        foreach ($event->jackknife as $jack) {
            $lines[] = 'JACK ' . $jack->station->code . ' dx=' . fixed($jack->dx, 1) . ' dy=' . fixed($jack->dy, 1)
                . ' dz=' . fixed($jack->dz, 1) . ' shift=' . fixed($jack->shift, 1);
        }
        $lines[] = 'JACKKNIFE max=' . fixed($event->worstJackknife->shift, 1) . ' station=' . $event->worstJackknife->station->code;
    }
    $lines[] = 'FIT n=' . $fit->n . ' velocity=' . fixed($fit->velocity, 1) . ' intercept=' . fixed($fit->intercept, 4) . ' rms=' . fixed($fit->rms, 4);
    foreach ($clusters as $cluster) {
        if (count($cluster->members) < 2) {
            continue;
        }
        $numbers = array_map(fn($event) => $event->number, $cluster->members);
        $lines[] = 'CLUSTER ' . $cluster->number . ' events=' . implode(',', $numbers) . ' x=' . fixed($cluster->x, 1)
            . ' y=' . fixed($cluster->y, 1) . ' z=' . fixed($cluster->z, 1) . ' span=' . fixed($cluster->span, 3);
    }
    $lines[] = 'ADDED';
    foreach ($added as $pick) {
        $lines[] = $pick->station->code . ' sample=' . $pick->sample . ' event=' . $pick->event . ' res=' . fixed($pick->residual, 4);
    }
    $depths = array_map(fn($event) => $event->relocation->point->z, $events);
    $quality = fn($code) => count(array_filter($events, fn($event) => $event->quality === $code));
    $meanRms = sumValues(array_map(fn($event) => $event->relocation->rms, $events)) / count($events);
    $rejected = count(array_filter($candidates, fn($candidate) => $candidate->rejected));
    $unassociated = count(array_filter($picks, fn($pick) => $pick->state === 'unassociated'));
    $lines[] = 'SUMMARY picks=' . count($picks) . ' candidates=' . count($candidates) . ' events=' . count($events)
        . ' rejected=' . $rejected . ' unassociated=' . $unassociated;
    $lines[] = 'DEPTH min=' . fixed(min($depths), 1) . ' median=' . fixed(median($depths), 1) . ' max=' . fixed(max($depths), 1);
    $lines[] = 'QUALITY A=' . $quality('A') . ' B=' . $quality('B') . ' C=' . $quality('C') . ' mean_rms=' . fixed($meanRms, 4);
    return $lines;
}

function picksLines(array $picks): array
{
    $lines = ['station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual'];
    foreach ($picks as $pick) {
        $residual = $pick->state === 'used' || $pick->state === 'added' ? fixed($pick->residual, 4) : '-';
        $lines[] = implode(',', [$pick->station->code, $pick->sample, timeNotation($pick->sample), $pick->duration,
            fixed($pick->snr, 2), $pick->amplitude, $pick->clipped ? 'yes' : 'no', $pick->event, $pick->state, $residual]);
    }
    return $lines;
}

function catalogLines(array $events): array
{
    $lines = ['event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster'];
    foreach ($events as $event) {
        $point = $event->relocation->point;
        $ellipse = $event->ellipse;
        $lines[] = implode(',', [$event->number, fixed($point->t0, 3), fixed($point->x, 1), fixed($point->y, 1),
            fixed($point->z, 1), fixed($event->relocation->rms, 4), count($event->used), fixed($event->gap, 1),
            fixed($event->dmin, 1), fixed($ellipse->smaj, 1), fixed($ellipse->smin, 1), fixed($ellipse->az, 1),
            fixed($ellipse->erz, 1), fixed($event->ml, 2), fixed($event->md, 2), $event->quality, $event->cluster]);
    }
    return $lines;
}

function stationsLines(array $stations): array
{
    $lines = [];
    foreach ($stations as $station) {
        $stats = $station->stats;
        $count = fn($state) => count(array_filter($stats->picks, fn($pick) => $pick->state === $state));
        $first = array_map(fn($pick) => $pick->firstResidual, $station->used);
        $after = array_map(fn($pick) => $pick->residual, $station->used);
        $lines[] = 'STATION ' . $station->code . ' x=' . $station->x . ' y=' . $station->y . ' elevation=' . $station->elevation;
        $lines[] = 'SAMPLES start=' . $station->start . ' count=' . count($station->samples) . ' mean=' . $stats->mean
            . ' noise=' . fixed($stats->noise, 1) . ' peak=' . $stats->peak . ' clipped=' . $stats->clippedSamples;
        $lines[] = 'TRIGGERS total=' . $stats->triggers . ' short=' . $stats->shortTriggers . ' picks=' . count($stats->picks);
        $lines[] = 'PICKS used=' . $count('used') . ' dropped=' . $count('dropped') . ' added=' . $count('added')
            . ' rejected=' . $count('rejected') . ' unassociated=' . $count('unassociated');
        $lines[] = 'RESIDUALS n=' . count($station->used) . ' rms=' . fixed(rms($first), 4)
            . ' correction=' . fixed($station->correction, 4) . ' after=' . fixed(rms($after), 4);
        $lines[] = 'MAGNITUDES n=' . count($station->magnitudePicks) . ' correction=' . fixed($station->magnitudeCorrection, 2);
    }
    return $lines;
}

function chartGrid(int $width, int $height): array
{
    return array_fill(0, $height, str_repeat(' ', $width));
}

function framed(array $grid): array
{
    $border = '+' . str_repeat('-', strlen($grid[0])) . '+';
    $lines = [$border];
    foreach ($grid as $row) {
        $lines[] = '|' . $row . '|';
    }
    $lines[] = $border;
    return $lines;
}

function timelineLines(array $events, object $params): array
{
    [$duration, $width, $low, $high, $height] = $params->timeline;
    $width = (int) $width;
    $height = (int) $height;
    $grid = chartGrid($width, $height);
    foreach ($events as $event) {
        if ($event->ml === null) {
            continue;
        }
        $time = scaled($event->relocation->point->t0, 3);
        $h = $event->hundredths;
        if ($time < 0 || $time >= 1000 * $duration || $h < 100 * $low) {
            continue;
        }
        $column = floorQuotient($time * $width, 1000 * $duration);
        $level = min(floorQuotient(($h - 100 * $low) * $height, 100 * ($high - $low)), $height - 1);
        for ($k = 0; $k <= $level; $k++) {
            $row = $height - 1 - $k;
            if ($k === $level) {
                $grid[$row][$column] = 'o';
            } elseif ($grid[$row][$column] === ' ') {
                $grid[$row][$column] = '|';
            }
        }
    }
    return array_merge(['TIMELINE t=0..' . $duration . ' ML=' . $low . '..' . $high], framed($grid));
}

function magnitudesLines(array $events, object $statistics, object $params): array
{
    $lines = [];
    foreach ($events as $event) {
        $lines[] = 'EVENT ' . $event->number . ' ML=' . fixed($event->ml, 2) . ' n=' . count($event->unclipped) . ' MD=' . fixed($event->md, 2);
        foreach ($event->used as $pick) {
            $line = $pick->station->code . ' r=' . fixed($pick->distanceKm, 3) . ' amp=' . $pick->amplitude;
            $line .= $pick->clipped ? ' clipped' : ' ml=' . fixed($pick->ml, 2) . ' res=' . fixed($pick->mlResidual, 2);
            $lines[] = $line . ' dur=' . $pick->duration . ' md=' . fixed($pick->md, 2);
        }
    }
    $lines[] = 'CORRECTED';
    foreach ($events as $event) {
        $lines[] = 'EVENT ' . $event->number . ' MLC=' . fixed($event->mlc, 2);
    }
    $lines[] = 'FMD';
    $frequency = $statistics->frequency;
    $cumulative = $statistics->measured;
    for ($value = $frequency->minimum; $value <= $frequency->maximum; $value++) {
        $count = $frequency->frequencies[$value] ?? 0;
        $lines[] = 'M=' . classNotation($value) . ' N=' . $count . ' CUM=' . $cumulative;
        $cumulative -= $count;
    }
    $relation = $statistics->relation;
    $lines[] = 'MC ' . classNotation($frequency->completeness);
    $lines[] = 'BVALUE ' . fixed($frequency->b, 3) . ' SIGMA ' . fixed($frequency->sigma, 3) . ' N ' . $frequency->count;
    $lines[] = 'AVALUE ' . fixed($frequency->a, 3);
    $lines[] = 'MLMD n=' . $relation->n . ' slope=' . fixed($relation->slope, 3) . ' intercept=' . fixed($relation->intercept, 3)
        . ' r=' . fixed($relation->r, 3) . ' mean_diff=' . fixed($relation->meanDifference, 3);
    return array_merge($lines, timelineLines($events, $params));
}

function mapLines(array $stations, array $events, object $params): array
{
    [$xmin, $xmax, $ymin, $ymax] = $params->mapArea;
    [$width, $mapHeight] = $params->mapSize;
    [$zmax, $sectionHeight] = $params->section;
    $width = (int) $width;
    $mapHeight = (int) $mapHeight;
    $sectionHeight = (int) $sectionHeight;
    $map = chartGrid($width, $mapHeight);
    $eastWest = chartGrid($width, $sectionHeight);
    $northSouth = chartGrid($width, $sectionHeight);
    $withinX = fn($x) => 10 * $xmin <= $x && $x < 10 * $xmax;
    $withinY = fn($y) => 10 * $ymin <= $y && $y < 10 * $ymax;
    $xColumn = fn($x) => floorQuotient(($x - 10 * $xmin) * $width, 10 * ($xmax - $xmin));
    $yColumn = fn($y) => floorQuotient(($y - 10 * $ymin) * $width, 10 * ($ymax - $ymin));
    $mapPosition = fn($x, $y) => $withinX($x) && $withinY($y)
        ? [$xColumn($x), $mapHeight - 1 - floorQuotient(($y - 10 * $ymin) * $mapHeight, 10 * ($ymax - $ymin))] : null;
    $priorities = ['?' => 0, '.' => 1, 'o' => 2, 'O' => 3, '@' => 4, '^' => 5];
    $place = function (array &$grid, ?array $position, string $symbol) use ($priorities): void {
        if ($position === null) {
            return;
        }
        [$column, $row] = $position;
        $previous = $grid[$row][$column];
        if ($previous === ' ' || $priorities[$symbol] > $priorities[$previous]) {
            $grid[$row][$column] = $symbol;
        }
    };
    $eventPositions = [];
    foreach ($events as $event) {
        $point = $event->relocation->point;
        $x = scaled($point->x, 1);
        $y = scaled($point->y, 1);
        $z = scaled($point->z, 1);
        $h = $event->hundredths;
        $symbol = $h === null ? '?' : ($h < 100 ? '.' : ($h < 200 ? 'o' : ($h < 300 ? 'O' : '@')));
        $position = (object) ['event' => $event, 'symbol' => $symbol, 'map' => $mapPosition($x, $y),
            'ew' => $withinX($x) && $z < 10 * $zmax ? [$xColumn($x), floorQuotient($z * $sectionHeight, 10 * $zmax)] : null,
            'ns' => $withinY($y) && $z < 10 * $zmax ? [$yColumn($y), floorQuotient($z * $sectionHeight, 10 * $zmax)] : null];
        $place($map, $position->map, $symbol);
        $place($eastWest, $position->ew, $symbol);
        $place($northSouth, $position->ns, $symbol);
        $eventPositions[] = $position;
    }
    $stationPositions = [];
    foreach ($stations as $station) {
        $position = $mapPosition(10 * $station->x, 10 * $station->y);
        $place($map, $position, '^');
        $stationPositions[] = (object) ['station' => $station, 'position' => $position];
    }
    $lines = ['MAP x=' . $xmin . '..' . $xmax . ' y=' . $ymin . '..' . $ymax];
    array_push($lines, ...framed($map));
    $lines[] = 'SECTION EW x=' . $xmin . '..' . $xmax . ' z=0..' . $zmax;
    array_push($lines, ...framed($eastWest));
    $lines[] = 'SECTION NS y=' . $ymin . '..' . $ymax . ' z=0..' . $zmax;
    array_push($lines, ...framed($northSouth));
    $lines[] = 'LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML';
    $positionText = fn($position) => $position === null ? 'outside' : implode(',', $position);
    foreach ($stationPositions as $item) {
        $lines[] = 'STATION ' . $item->station->code . ' map=' . $positionText($item->position);
    }
    foreach ($eventPositions as $item) {
        $lines[] = 'EVENT ' . $item->event->number . ' ' . $item->symbol . ' map=' . $positionText($item->map)
            . ' ew=' . $positionText($item->ew) . ' ns=' . $positionText($item->ns);
    }
    return $lines;
}

function main(): void
{
    [$stations, $params] = readInput();
    $picks = [];
    foreach ($stations as $station) {
        $station->used = [];
        $station->stats = detectPicks($station, $params);
        array_push($picks, ...$station->stats->picks);
    }
    usort($picks, fn($a, $b) => ($a->sample <=> $b->sample) ?: ($a->station->index <=> $b->station->index));
    $candidates = associate($picks, $params->associationWindow, $params->minStations);
    $events = processCandidates($candidates, $params);
    relocateEvents($stations, $events, $params);
    computeMagnitudes($stations, $events, $params);
    $fit = travelTimeFit($events);
    $clusters = clusterEvents($events, $params);
    $added = reassociate($picks, $events, $params);
    $statistics = catalogStatistics($events);
    $outputs = [
        'picks.csv' => picksLines($picks),
        'locations.txt' => locationsLines($stations, $picks, $candidates, $events, $fit, $clusters, $added, $params),
        'catalog.csv' => catalogLines($events),
        'magnitudes.txt' => magnitudesLines($events, $statistics, $params),
        'stations.txt' => stationsLines($stations),
        'map.txt' => mapLines($stations, $events, $params)
    ];
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    foreach ($outputs as $name => $lines) {
        file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
    }
}

main();
