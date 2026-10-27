<?php

require_once __DIR__ . '/records.php';
require_once __DIR__ . '/cleaning.php';
require_once __DIR__ . '/harmonic_fit.php';
require_once __DIR__ . '/predict.php';
require_once __DIR__ . '/report.php';

function sumValues($items, $value = null) {
    $total = 0.0;
    foreach ($items as $item) $total += $value === null ? $item : $value($item);
    return $total;
}

function meanValues($items, $value = null) {
    return sumValues($items, $value) / count($items);
}

function choose($items, $field, $largest = true) {
    $best = null;
    foreach ($items as $item) if ($best === null || ($largest ? $item->$field > $best->$field : $item->$field < $best->$field)) $best = $item;
    return $best;
}

function selectConstituents($constituents, $length, $rayleigh) {
    $selected = $statuses = [];
    foreach ($constituents as $constituent) {
        if ($constituent->speed * $length < 360 * $rayleigh) {
            $statuses[$constituent->name] = 'short';
            continue;
        }
        $conflict = null;
        foreach ($selected as $other) if (abs($constituent->speed - $other->speed) * $length < 360 * $rayleigh) {
            $conflict = $other;
            break;
        }
        if ($conflict !== null) $statuses[$constituent->name] = 'conflict:' . $conflict->name;
        else {
            $statuses[$constituent->name] = 'fitted';
            $selected[] = $constituent;
        }
    }
    return (object)compact('selected', 'statuses');
}

function checkStation($station, $rows, $constituents, $params) {
    $numeric = array_values(array_filter($rows, fn($row) => $row->value !== null));
    $first = $numeric[0]->time;
    $last = $numeric[count($numeric) - 1]->time;
    $length = $last - $first;
    $byTime = [];
    foreach ($rows as $row) $byTime[$row->time] = $row;
    $reasons = [];
    for ($time = $first; $time <= $last; $time++) {
        if (!isset($byTime[$time])) $reasons[$time] = 'absent';
        elseif ($byTime[$time]->value === null) $reasons[$time] = 'na';
    }
    $flats = flatRuns($numeric, $params->flatRun);
    foreach ($flats as $run) for ($time = $run->start + 1; $time <= $run->end; $time++) $reasons[$time] = 'flat';
    $candidates = array_values(array_filter($numeric, fn($row) => !isset($reasons[$row->time])));
    $selection = selectConstituents($constituents, $length, $params->rayleigh);
    $preliminary = fitHarmonics($candidates, $selection->selected);
    $squares = 0.0;
    foreach ($candidates as $row) {
        $row->preliminary = $row->value - level($preliminary, $row->time);
        $squares += $row->preliminary * $row->preliminary;
    }
    $prefitRms = sqrt($squares / count($candidates));
    $test = spikeTests($candidates, $params->spike);
    $spikes = $test['spikes'];
    foreach ($spikes as $spike) $reasons[$spike->time] = 'spike';
    $usable = array_values(array_filter($candidates, fn($row) => !isset($reasons[$row->time])));
    $counts = ['rows' => count($rows), 'numeric' => count($numeric), 'na' => 0, 'absent' => 0, 'flat' => 0, 'spikes' => 0, 'usable' => count($usable)];
    foreach ($reasons as $reason) $counts[$reason === 'spike' ? 'spikes' : $reason]++;
    return (object)['code' => $station->code, 'name' => $station->name, 'first' => $first, 'last' => $last, 'length' => $length,
        'selection' => $selection, 'candidates' => $candidates, 'usable' => $usable, 'counts' => $counts, 'flats' => $flats,
        'prefitRms' => $prefitRms, 'tested' => $test['tested'], 'spikes' => $spikes, 'gaps' => gaps($first, $last, $reasons)];
}

function finalFit($station, $params) {
    $model = fitHarmonics($station->usable, $station->selection->selected);
    $residuals = [];
    $squares = $maxAbs = 0.0;
    foreach ($station->usable as $row) {
        $row->fitted = level($model, $row->time);
        $row->residual = $row->value - $row->fitted;
        $residuals[$row->time] = $row->residual;
        $squares += $row->residual * $row->residual;
        $maxAbs = max($maxAbs, abs($row->residual));
    }
    $dof = count($station->usable) - $model->unknowns;
    $variance = $squares / $dof;
    $observedMean = meanValues($station->usable, fn($row) => $row->value);
    $centeredSquares = $lagProduct = $lagSquares = 0.0;
    foreach ($station->usable as $row) {
        $difference = $row->value - $observedMean;
        $centeredSquares += $difference * $difference;
        if (array_key_exists($row->time + 1, $residuals)) {
            $lagProduct += $row->residual * $residuals[$row->time + 1];
            $lagSquares += $row->residual * $row->residual;
        }
    }
    foreach ($model->constituents as $index => $constituent) {
        $a = $constituent->a;
        $b = $constituent->b;
        $amplitude = $constituent->amplitude;
        $ia = 2 * $index + 1;
        $ib = 2 * $index + 2;
        $va = $variance * $model->inverse[$ia][$ia];
        $vb = $variance * $model->inverse[$ib][$ib];
        $cab = $variance * $model->inverse[$ia][$ib];
        $constituent->amplitudeError = sqrt($a * $a * $va + $b * $b * $vb + 2 * $a * $b * $cab) / $amplitude;
        $constituent->phaseError = sqrt($b * $b * $va + $a * $a * $vb - 2 * $a * $b * $cab) / ($amplitude * $amplitude) * 180 / TIDE_PI;
        $ratio = $amplitude / $constituent->amplitudeError;
        $constituent->snr = $ratio * $ratio;
        $constituent->significant = $constituent->snr >= $params->snrMin ? 'yes' : 'no';
    }
    $fitted = [];
    foreach ($model->constituents as $item) $fitted[$item->name] = $item;
    $station->model = $model;
    $station->fittedConstituents = $fitted;
    $station->residuals = $residuals;
    $station->statistics = (object)['dof' => $dof, 'rms' => sqrt($squares / count($station->usable)), 'maxAbs' => $maxAbs,
        'explained' => 100 * (1 - $squares / $centeredSquares), 'lag1' => $lagProduct / $lagSquares];
    $station->top = $station->usable;
    usort($station->top, fn($a, $b) => (abs($b->residual) <=> abs($a->residual)) ?: ($a->time <=> $b->time));
    $station->top = array_slice($station->top, 0, $params->topResiduals);
}

function predictions($station, $params) {
    $station->predictions = [];
    for ($i = 0; $i <= $params->hours; $i++) $station->predictions[] = level($station->model, $params->start + $i);
    $extrema = gridExtrema($station->model, $params->start, $params->hours, $params->grid);
    $station->rawExtrema = count($extrema);
    while (count($extrema) >= 2) {
        $pair = 0;
        $difference = abs($extrema[0]->height - $extrema[1]->height);
        for ($i = 1; $i + 1 < count($extrema); $i++) {
            $candidate = abs($extrema[$i]->height - $extrema[$i + 1]->height);
            if ($candidate < $difference) {
                $pair = $i;
                $difference = $candidate;
            }
        }
        if ($difference >= $params->minRange) break;
        array_splice($extrema, $pair, 2);
    }
    $byDay = [];
    foreach ($extrema as $extremum) {
        $extremum->minute = (int)floor($extremum->refinedMinute + 0.5);
        $extremum->day = (int)floor($extremum->minute / 1440);
        $extremum->label = $extremum->kind === 'high' ? 'LHW' : 'HLW';
        if (!isset($byDay[$extremum->day])) $byDay[$extremum->day] = ['highs' => [], 'lows' => []];
        $byDay[$extremum->day][$extremum->kind === 'high' ? 'highs' : 'lows'][] = $extremum;
    }
    foreach ($byDay as $group) {
        $highest = choose($group['highs'], 'height');
        $lowest = choose($group['lows'], 'height', false);
        if ($highest !== null) $highest->label = 'HHW';
        if ($lowest !== null) $lowest->label = 'LLW';
    }
    $daily = [];
    for ($offset = 0; $offset < intdiv($params->hours, 24); $offset++) {
        $day = intdiv($params->start, 24) + $offset;
        $group = $byDay[$day] ?? ['highs' => [], 'lows' => []];
        $highest = choose($group['highs'], 'height');
        $lowest = choose($group['lows'], 'height', false);
        $hhw = $highest === null ? null : $highest->height;
        $llw = $lowest === null ? null : $lowest->height;
        $daily[] = (object)['day' => $day, 'highCount' => count($group['highs']), 'lowCount' => count($group['lows']), 'hhw' => $hhw, 'llw' => $llw,
            'range' => $hhw === null || $llw === null ? null : $hhw - $llw];
    }
    $station->extrema = $extrema;
    $station->highs = array_values(array_filter($extrema, fn($item) => $item->kind === 'high'));
    $station->lows = array_values(array_filter($extrema, fn($item) => $item->kind === 'low'));
    $station->daily = $daily;
}

function validation($station, $constituents, $params) {
    $split = $station->first + intdiv($station->length, 2);
    $training = $test = [];
    foreach ($station->usable as $row) {
        if ($row->time <= $split) $training[] = $row;
        else $test[] = $row;
    }
    $selection = selectConstituents($constituents, $training[count($training) - 1]->time - $training[0]->time, $params->rayleigh);
    $model = fitHarmonics($training, $selection->selected);
    $observedMean = meanValues($test, fn($row) => $row->value);
    $squares = $inSampleSquares = $centeredSquares = 0.0;
    foreach ($test as $row) {
        $error = $row->value - level($model, $row->time);
        $centered = $row->value - $observedMean;
        $squares += $error * $error;
        $inSampleSquares += $row->residual * $row->residual;
        $centeredSquares += $centered * $centered;
    }
    return (object)['split' => $split, 'train' => count($training), 'test' => count($test), 'constituents' => count($selection->selected),
        'rms' => sqrt($squares / count($test)), 'inSampleRms' => sqrt($inSampleSquares / count($test)), 'skill' => 1 - $squares / $centeredSquares];
}

function residualEvents($station, $settings) {
    $events = [];
    $current = null;
    $finish = function() use (&$current, &$events, $settings) {
        if ($current !== null && $current->end - $current->start + 1 >= $settings->hours) $events[] = $current;
        $current = null;
    };
    foreach ($station->usable as $row) {
        $type = $row->residual > $settings->threshold ? 'positive' : ($row->residual < -$settings->threshold ? 'negative' : null);
        if ($current !== null && ($type !== $current->type || $row->time !== $current->end + 1)) $finish();
        if ($type === null) continue;
        if ($current === null) $current = (object)['type' => $type, 'start' => $row->time, 'end' => $row->time, 'peak' => $row->residual, 'peakTime' => $row->time];
        else {
            $current->end = $row->time;
            if ($type === 'positive' ? $row->residual > $current->peak : $row->residual < $current->peak) {
                $current->peak = $row->residual;
                $current->peakTime = $row->time;
            }
        }
    }
    $finish();
    return $events;
}

function dailyMeans($station) {
    $weights = [0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1];
    $usable = [];
    foreach ($station->usable as $row) $usable[$row->time] = $row->value;
    $filledLevels = [];
    for ($time = $station->first; $time <= $station->last; $time++) {
        $filledLevels[] = array_key_exists($time, $usable) ? $usable[$time] : level($station->model, $time);
    }
    $days = [];
    for ($day = intdiv($station->first, 24); $day <= intdiv($station->last, 24); $day++) {
        $noon = $day * 24 + 12;
        if ($noon - 19 < $station->first || $noon + 19 > $station->last) continue;
        $total = 0.0;
        $filled = 0;
        for ($offset = -19; $offset <= 19; $offset++) {
            $time = $noon + $offset;
            $total += $weights[abs($offset)] * $filledLevels[$time - $station->first];
            if (!array_key_exists($time, $usable)) $filled++;
        }
        $days[] = (object)['day' => $day, 'level' => $total / 30, 'filled' => $filled];
    }
    $average = meanValues($days, fn($entry) => $entry->level);
    $firstDay = $days[0]->day;
    $meanDay = meanValues($days, fn($entry) => $entry->day - $firstDay);
    $numerator = $denominator = 0.0;
    foreach ($days as $entry) {
        $x = $entry->day - $firstDay - $meanDay;
        $numerator += $x * ($entry->level - $average);
        $denominator += $x * $x;
    }
    return (object)['days' => $days, 'average' => $average, 'slope' => 1000 * ($numerator / $denominator),
        'maximum' => choose($days, 'level'), 'minimum' => choose($days, 'level', false)];
}

function tidalCharacteristics($station, $params) {
    $m2 = $station->fittedConstituents['M2'];
    $s2 = $station->fittedConstituents['S2'];
    $k1 = $station->fittedConstituents['K1'];
    $o1 = $station->fittedConstituents['O1'];
    $m4 = $station->fittedConstituents['M4'];
    $form = ($k1->amplitude + $o1->amplitude) / ($m2->amplitude + $s2->amplitude);
    $type = $form < 0.25 ? 'semidiurnal' : ($form < 1.5 ? 'mixed_semidiurnal' : ($form < 3 ? 'mixed_diurnal' : 'diurnal'));
    $mhhw = meanValues(array_values(array_filter($station->daily, fn($day) => $day->hhw !== null)), fn($day) => $day->hhw);
    $mllw = meanValues(array_values(array_filter($station->daily, fn($day) => $day->llw !== null)), fn($day) => $day->llw);
    $mhw = meanValues($station->highs, fn($item) => $item->height);
    $mlw = meanValues($station->lows, fn($item) => $item->height);
    $amplitudeSum = sumValues($station->model->constituents, fn($item) => $item->amplitude);
    $completeDays = array_values(array_filter($station->daily, fn($day) => $day->range !== null));
    $rises = $falls = [];
    for ($i = 1; $i < count($station->extrema); $i++) {
        $previous = $station->extrema[$i - 1];
        $current = $station->extrema[$i];
        if ($previous->kind === 'low' && $current->kind === 'high') $rises[] = $current->minute - $previous->minute;
        if ($previous->kind === 'high' && $current->kind === 'low') $falls[] = $current->minute - $previous->minute;
    }
    $relativePhase = 2 * $m2->phase - $m4->phase;
    while ($relativePhase < 0) $relativePhase += 360;
    while ($relativePhase >= 360) $relativePhase -= 360;
    $above = $below = 0;
    foreach ($station->predictions as $value) {
        if ($value > $mhhw) $above++;
        if ($value < $mllw) $below++;
    }
    return (object)['form' => $form, 'type' => $type, 'spring' => 2 * ($m2->amplitude + $s2->amplitude), 'neap' => 2 * ($m2->amplitude - $s2->amplitude),
        'mhhw' => $mhhw, 'mllw' => $mllw, 'mhw' => $mhw, 'mlw' => $mlw, 'mtl' => ($mhw + $mlw) / 2, 'dtl' => ($mhhw + $mllw) / 2,
        'mn' => $mhw - $mlw, 'gt' => $mhhw - $mllw, 'hat' => $station->model->mean + $amplitudeSum, 'lat' => $station->model->mean - $amplitudeSum,
        'highest' => choose($station->highs, 'height'), 'lowest' => choose($station->lows, 'height', false),
        'widest' => choose($completeDays, 'range'), 'narrowest' => choose($completeDays, 'range', false),
        'above' => 100 * $above / ($params->hours + 1), 'below' => 100 * $below / ($params->hours + 1),
        'rise' => meanValues($rises), 'fall' => meanValues($falls), 'm4Ratio' => $m4->amplitude / $m2->amplitude,
        'relativePhase' => $relativePhase, 'dominance' => $relativePhase < 180 ? 'flood' : 'ebb'];
}

function springNeap($station, $params) {
    $m2 = $station->fittedConstituents['M2'];
    $s2 = $station->fittedConstituents['S2'];
    $differenceSpeed = $s2->speed - $m2->speed;
    $differencePhase = $s2->phase - $m2->phase;
    $startQ = ($differenceSpeed * $params->start - $differencePhase) / 180;
    $endQ = ($differenceSpeed * ($params->start + $params->hours) - $differencePhase) / 180;
    $events = [];
    $first = (int)floor(min($startQ, $endQ)) - 1;
    $last = (int)ceil(max($startQ, $endQ)) + 1;
    for ($q = $first; $q <= $last; $q++) {
        $time = ($differencePhase + 180 * $q) / $differenceSpeed;
        if ($time >= $params->start && $time <= $params->start + $params->hours) {
            $events[] = (object)['type' => $q % 2 === 0 ? 'spring' : 'neap', 'minute' => (int)floor($time * 60 + 0.5)];
        }
    }
    return $events;
}

function cleaningLines($station, $params) {
    $dt = fn($time) => hourDatetime($params->epoch, $time);
    $count = $station->counts;
    $lines = ['station=' . $station->code . ' name=' . $station->name,
        'span start=' . $dt($station->first) . ' end=' . $dt($station->last) . ' hours=' . ($station->length + 1) . ' record_length=' . $station->length,
        'counts rows=' . $count['rows'] . ' numeric=' . $count['numeric'] . ' na=' . $count['na'] . ' absent=' . $count['absent'] . ' flat=' . $count['flat'] . ' spikes=' . $count['spikes'] . ' usable=' . $count['usable']];
    foreach ($station->flats as $run) $lines[] = 'flat start=' . $dt($run->start) . ' end=' . $dt($run->end) . ' value=' . real($run->value, 3) . ' removed=' . ($run->end - $run->start);
    $lines[] = 'spike_test window=' . $params->spike->window . ' candidates=' . count($station->candidates) . ' tested=' . $station->tested . ' prefit_rms=' . real($station->prefitRms, 4);
    foreach ($station->spikes as $spike) {
        $lines[] = 'spike time=' . $dt($spike->time) . ' value=' . real($spike->value, 3) . ' residual=' . real($spike->residual, 4)
            . ' median=' . real($spike->median, 4) . ' mad=' . real($spike->mad, 4) . ' limit=' . real($spike->limit, 4);
    }
    foreach ($station->gaps as $gap) $lines[] = 'gap start=' . $dt($gap->start) . ' end=' . $dt($gap->end) . ' hours=' . ($gap->end - $gap->start + 1) . ' cause=' . $gap->cause;
    return $lines;
}

function constituentLines($station, $constituents) {
    $lines = [];
    foreach ($constituents as $constituent) {
        $status = $station->selection->statuses[$constituent->name];
        $prefix = $station->code . ',' . $constituent->name . ',' . real($constituent->speed, 7) . ',' . $status;
        if ($status !== 'fitted') $lines[] = $prefix . ',,,,,,';
        else {
            $fitted = $station->fittedConstituents[$constituent->name];
            $lines[] = $prefix . ',' . real($fitted->amplitude, 4) . ',' . real($fitted->phase, 2) . ',' . real($fitted->amplitudeError, 4)
                . ',' . real($fitted->phaseError, 2) . ',' . real($fitted->snr, 1) . ',' . $fitted->significant;
        }
    }
    return $lines;
}

function extremeLines($station, $params) {
    $lines = ['station=' . $station->code . ' extremes=' . count($station->extrema) . ' raw=' . $station->rawExtrema . ' removed=' . ($station->rawExtrema - count($station->extrema))];
    foreach ($station->extrema as $i => $item) {
        $change = $i === 0 ? 'none' : real($item->height - $station->extrema[$i - 1]->height, 3);
        $lines[] = datetime($params->epoch, $item->minute) . ' ' . $item->label . ' ' . real($item->height, 3) . ' change=' . $change;
    }
    foreach ($station->daily as $day) {
        $lines[] = 'day date=' . dayDate($params->epoch, $day->day) . ' high_waters=' . $day->highCount . ' low_waters=' . $day->lowCount
            . ' hhw=' . real($day->hhw, 3) . ' llw=' . real($day->llw, 3) . ' range=' . real($day->range, 3);
    }
    return $lines;
}

function summaryLines($station, $params) {
    $dt = fn($time) => hourDatetime($params->epoch, $time);
    $minute = fn($time) => datetime($params->epoch, $time);
    $date = fn($day) => dayDate($params->epoch, $day);
    $stats = $station->statistics;
    $validation = $station->validation;
    $tide = $station->characteristics;
    $daily = $station->dailyMeans;
    $lines = ['[station ' . $station->code . '] ' . $station->name,
        'record first=' . $dt($station->first) . ' last=' . $dt($station->last) . ' length=' . $station->length . ' usable=' . count($station->usable),
        'fit constituents=' . count($station->model->constituents) . ' unknowns=' . $station->model->unknowns . ' dof=' . $stats->dof . ' mean_level=' . real($station->model->mean, 4),
        'residual rms=' . real($stats->rms, 4) . ' max_abs=' . real($stats->maxAbs, 4) . ' explained_percent=' . real($stats->explained, 4) . ' lag1_autocorrelation=' . real($stats->lag1, 4)];
    foreach ($station->top as $index => $row) $lines[] = 'top_residual rank=' . ($index + 1) . ' time=' . $dt($row->time) . ' observed=' . real($row->value, 3)
        . ' fitted=' . real($row->fitted, 4) . ' residual=' . real($row->residual, 4);
    $lines[] = 'validation split=' . $dt($validation->split) . ' train=' . $validation->train . ' test=' . $validation->test . ' constituents=' . $validation->constituents
        . ' rms=' . real($validation->rms, 4) . ' in_sample_rms=' . real($validation->inSampleRms, 4) . ' skill=' . real($validation->skill, 4);
    $lines[] = 'form_number=' . real($tide->form, 4) . ' type=' . $tide->type;
    $lines[] = 'ranges spring=' . real($tide->spring, 3) . ' neap=' . real($tide->neap, 3) . ' mn=' . real($tide->mn, 3) . ' gt=' . real($tide->gt, 3);
    $lines[] = 'asymmetry rise_minutes=' . real($tide->rise, 1) . ' fall_minutes=' . real($tide->fall, 1) . ' m4_m2_ratio=' . real($tide->m4Ratio, 4)
        . ' relative_phase=' . real($tide->relativePhase, 2) . ' dominance=' . $tide->dominance;
    $lines[] = 'datums mhhw=' . real($tide->mhhw, 3) . ' mhw=' . real($tide->mhw, 3) . ' mtl=' . real($tide->mtl, 3) . ' dtl=' . real($tide->dtl, 3)
        . ' mlw=' . real($tide->mlw, 3) . ' mllw=' . real($tide->mllw, 3);
    $lines[] = 'bounds hat=' . real($tide->hat, 3) . ' lat=' . real($tide->lat, 3);
    $lines[] = 'window high_waters=' . count($station->highs) . ' low_waters=' . count($station->lows) . ' highest=' . real($tide->highest->height, 3)
        . ' highest_time=' . $minute($tide->highest->minute) . ' lowest=' . real($tide->lowest->height, 3) . ' lowest_time=' . $minute($tide->lowest->minute);
    $lines[] = 'daily_range widest=' . real($tide->widest->range, 3) . ' widest_date=' . $date($tide->widest->day)
        . ' narrowest=' . real($tide->narrowest->range, 3) . ' narrowest_date=' . $date($tide->narrowest->day);
    $lines[] = 'exceedance above_mhhw=' . real($tide->above, 2) . ' below_mllw=' . real($tide->below, 2);
    foreach ($station->springNeap as $event) $lines[] = $event->type . ' time=' . $minute($event->minute);
    $lines[] = 'surges count=' . count($station->events) . ' threshold=' . real($params->surge->threshold, 3) . ' min_hours=' . $params->surge->hours;
    foreach ($station->events as $event) $lines[] = 'surge type=' . $event->type . ' start=' . $dt($event->start) . ' end=' . $dt($event->end) . ' hours=' . ($event->end - $event->start + 1)
        . ' peak=' . real($event->peak, 4) . ' peak_time=' . $dt($event->peakTime);
    $lines[] = 'daily_mean days=' . count($daily->days) . ' average=' . real($daily->average, 4) . ' slope_mm_per_day=' . real($daily->slope, 3)
        . ' max=' . real($daily->maximum->level, 4) . ' max_date=' . $date($daily->maximum->day) . ' min=' . real($daily->minimum->level, 4) . ' min_date=' . $date($daily->minimum->day);
    foreach ($daily->days as $day) $lines[] = 'daily_mean date=' . $date($day->day) . ' level=' . real($day->level, 4) . ' filled=' . $day->filled;
    return $lines;
}

function waterLag($waters, $reference) {
    $total = 0.0;
    foreach ($waters as $water) {
        $nearest = $reference[0];
        for ($i = 1; $i < count($reference); $i++) {
            if (abs($reference[$i]->minute - $water->minute) < abs($nearest->minute - $water->minute)) $nearest = $reference[$i];
        }
        $total += $water->minute - $nearest->minute;
    }
    return $total / count($waters);
}

function comparisonLines($stations, $params) {
    foreach ($stations as $station) if ($station->code === $params->reference) {
        $reference = $station;
        break;
    }
    $lines = ['[comparison] reference=' . $params->reference];
    foreach ($stations as $station) {
        if ($station->code === $reference->code) continue;
        $tide = $station->characteristics;
        $lines[] = $station->code . ' tide hw_lag_min=' . real(waterLag($station->highs, $reference->highs), 1)
            . ' lw_lag_min=' . real(waterLag($station->lows, $reference->lows), 1) . ' range_ratio=' . real($tide->gt / $reference->characteristics->gt, 4)
            . ' mtl_diff=' . real($tide->mtl - $reference->characteristics->mtl, 3);
        foreach (['M2', 'S2', 'K1', 'O1'] as $name) {
            $own = $station->fittedConstituents[$name];
            $other = $reference->fittedConstituents[$name];
            $phase = $own->phase - $other->phase;
            if ($phase > 180) $phase -= 360;
            if ($phase <= -180) $phase += 360;
            $lines[] = $station->code . ' ' . $name . ' amplitude_ratio=' . real($own->amplitude / $other->amplitude, 4)
                . ' phase_diff=' . real($phase, 2) . ' time_lag_min=' . real($phase / $own->speed * 60, 1);
        }
    }
    return $lines;
}

function correlation($first, $second, $lag) {
    $pairs = [];
    foreach ($first->usable as $row) {
        if (array_key_exists($row->time + $lag, $second->residuals)) $pairs[] = [$row->residual, $second->residuals[$row->time + $lag]];
    }
    $mx = meanValues($pairs, fn($pair) => $pair[0]);
    $my = meanValues($pairs, fn($pair) => $pair[1]);
    $sxy = $sxx = $syy = 0.0;
    foreach ($pairs as $pair) {
        $x = $pair[0] - $mx;
        $y = $pair[1] - $my;
        $sxy += $x * $y;
        $sxx += $x * $x;
        $syy += $y * $y;
    }
    return (object)['lag' => $lag, 'rho' => $sxy / sqrt($sxx * $syy), 'pairs' => count($pairs)];
}

function correlationLines($stations, $maximumLag) {
    $lines = ['[correlation] max_lag=' . $maximumLag];
    for ($i = 0; $i < count($stations); $i++) for ($j = $i + 1; $j < count($stations); $j++) {
        $best = null;
        $zero = null;
        for ($lag = -$maximumLag; $lag <= $maximumLag; $lag++) {
            $candidate = correlation($stations[$i], $stations[$j], $lag);
            if ($lag === 0) $zero = $candidate->rho;
            if ($best === null || $candidate->rho > $best->rho || ($candidate->rho === $best->rho &&
                (abs($lag) < abs($best->lag) || (abs($lag) === abs($best->lag) && $lag < $best->lag)))) $best = $candidate;
        }
        $lines[] = $stations[$i]->code . '-' . $stations[$j]->code . ' lag0=' . real($zero, 4) . ' best_lag=' . $best->lag . ' best=' . real($best->rho, 4) . ' pairs=' . $best->pairs;
    }
    return $lines;
}

function plot($stations, $params) {
    foreach ($stations as $item) if ($item->code === $params->plot->code) {
        $station = $item;
        break;
    }
    $hours = $params->plot->hours;
    $top = $params->plot->top;
    $bottom = $params->plot->bottom;
    $step = $params->plot->step;
    $rowCount = intdiv($top - $bottom, $step) + 1;
    $cells = array_fill(0, $rowCount, array_fill(0, $hours, ' '));
    $heights = [];
    for ($row = 0; $row < $rowCount; $row++) $heights[] = $top - $row * $step;
    $baseline = (int)floor(($top - 100 * $station->model->mean) / $step + 0.5);
    if ($baseline >= 0 && $baseline < $rowCount) $cells[$baseline] = array_fill(0, $hours, '-');
    $marks = [];
    foreach ($station->extrema as $extremum) {
        $column = intdiv($extremum->minute - 60 * $params->start + 30, 60);
        if ($column >= 0 && $column < $hours) $marks[$column] = $extremum->kind === 'high' ? 'H' : 'L';
    }
    for ($column = 0; $column < $hours; $column++) {
        $row = (int)floor(($top - 100 * $station->predictions[$column]) / $step + 0.5);
        if ($row < 0) $cells[0][$column] = '^';
        elseif ($row >= $rowCount) $cells[$rowCount - 1][$column] = 'v';
        else $cells[$row][$column] = $marks[$column] ?? '*';
    }
    return array_merge(['[plot] station=' . $station->code . ' start=' . hourDatetime($params->epoch, $params->start) . ' hours=' . $hours . ' step_cm=' . $step], plotLines($cells, $heights));
}

$data = readAll();
$params = $data['params'];
$constituents = $data['constituents'];
$stations = [];
$files = ['cleaning.txt' => [], 'constituents.csv' => ['station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant'],
    'predictions.csv' => ['time,' . implode(',', array_map(fn($station) => $station->code, $params->stations))], 'extremes.txt' => [], 'summary.txt' => []];
foreach ($params->stations as $source) {
    $station = checkStation($source, $data['observations'][$source->code], $constituents, $params);
    finalFit($station, $params);
    predictions($station, $params);
    $station->validation = validation($station, $constituents, $params);
    $station->events = residualEvents($station, $params->surge);
    $station->dailyMeans = dailyMeans($station);
    $station->characteristics = tidalCharacteristics($station, $params);
    $station->springNeap = springNeap($station, $params);
    $stations[] = $station;
    foreach (cleaningLines($station, $params) as $line) $files['cleaning.txt'][] = $line;
    foreach (constituentLines($station, $constituents) as $line) $files['constituents.csv'][] = $line;
    foreach (extremeLines($station, $params) as $line) $files['extremes.txt'][] = $line;
    foreach (summaryLines($station, $params) as $line) $files['summary.txt'][] = $line;
}
for ($index = 0; $index <= $params->hours; $index++) {
    $values = [];
    foreach ($stations as $station) $values[] = real($station->predictions[$index], 3);
    $files['predictions.csv'][] = hourDatetime($params->epoch, $params->start + $index) . ',' . implode(',', $values);
}
foreach (comparisonLines($stations, $params) as $line) $files['summary.txt'][] = $line;
foreach (correlationLines($stations, $params->correlationLag) as $line) $files['summary.txt'][] = $line;
foreach (plot($stations, $params) as $line) $files['summary.txt'][] = $line;
writeFiles($files);
