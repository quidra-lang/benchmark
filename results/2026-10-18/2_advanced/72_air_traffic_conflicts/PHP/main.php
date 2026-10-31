<?php

require_once __DIR__ . '/flight_plans.php';
require_once __DIR__ . '/trajectory.php';
require_once __DIR__ . '/conflict.php';
require_once __DIR__ . '/resolution.php';
require_once __DIR__ . '/report.php';

const PI_VALUE = 3.141592653589793;

function names($object) { $keys = array_keys($object); sort($keys, SORT_STRING); return $keys; }
function samples($params) { $result = []; for ($t = $params['sampleStart']; $t < $params['sampleEnd']; $t += 60) $result[] = $t; return $result; }
function pair_key($pair) { return $pair[0] . '-' . $pair[1]; }
function append_lines(&$target, $lines) { foreach ($lines as $line) $target[] = $line; }

function blockers($changed, $candidate, $partner, $trajectories, $ignored, $start, $params)
{
    $blocked = [];
    foreach (names($trajectories) as $other) {
        if ($other === $changed) continue;
        $pair = [$changed, $other]; sort($pair, SORT_STRING);
        if (isset($ignored[pair_key($pair)])) continue;
        $first = $pair[0] === $changed ? $candidate : $trajectories[$pair[0]];
        $second = $pair[1] === $changed ? $candidate : $trajectories[$pair[1]];
        foreach (pair_conflicts($pair[0], $first, $pair[1], $second, $params['dh'], $params['dv']) as $conflict) {
            if ($other === $partner || $conflict['start'] < $start + $params['lookahead']) $blocked[] = $conflict;
        }
    }
    usort($blocked, fn($a, $b) => ($a['start'] <=> $b['start']) ?: strcmp($a['name'], $b['name']));
    return count($blocked) ? $blocked[0] : null;
}

function resolve_conflicts($initial, $types, $params)
{
    $plans = $initial; $trajectories = [];
    foreach ($plans as $code => $plan) $trajectories[$code] = build_trajectory($plan, $types);
    $unresolved = []; $resolved = []; $rounds = []; $unresolvedConflicts = [];
    while (true) {
        $target = null;
        foreach (all_conflicts($trajectories, $params['dh'], $params['dv']) as $conflict) if (!isset($unresolved[pair_key($conflict['pair'])])) { $target = $conflict; break; }
        if ($target === null) break;
        $pair = $target['pair']; [$low, $high] = priority_order($plans[$pair[0]], $plans[$pair[1]]);
        $round = ['number' => count($rounds) + 1, 'target' => $target, 'trials' => [], 'accepted' => null];
        foreach ([[$low, $high], [$high, $low]] as [$flight, $partner]) {
            if ($round['accepted'] !== null) break;
            foreach (manoeuvres($params['maxDelay']) as [$name, $value]) {
                $next = propose($plans[$flight], $name, $value, $types, $params); $attempt = ['flight' => $flight, 'name' => $name];
                if ($next === null) $attempt['status'] = 'infeasible';
                else {
                    $path = build_trajectory($next, $types);
                    $blocking = blockers($flight, $path, $partner, $trajectories, $unresolved, $target['start'], $params);
                    if ($blocking !== null) { $attempt['status'] = 'blocked'; $attempt['blocker'] = $blocking; }
                    else {
                        $attempt['status'] = 'accepted'; $next['history'][] = $name;
                        $plans[$flight] = $next; $trajectories[$flight] = $path; $round['accepted'] = $attempt;
                    }
                }
                $round['trials'][] = $attempt;
                if ($round['accepted'] !== null) break;
            }
        }
        $key = pair_key($pair);
        if ($round['accepted'] === null) { $unresolved[$key] = true; $unresolvedConflicts[] = $target; }
        else $resolved[$key] = true;
        $rounds[] = $round;
    }
    return compact('plans', 'trajectories', 'rounds', 'unresolved', 'resolved', 'unresolvedConflicts');
}

function track($segment)
{
    $theta = atan2($segment['velocity'][0], $segment['velocity'][1]) * 180 / PI_VALUE;
    return $theta < 0 ? $theta + 360 : $theta;
}

function contains($sector, $p)
{
    return $sector['x1'] / 10 <= $p[0] && $p[0] < $sector['x2'] / 10 && $sector['y1'] / 10 <= $p[1] && $p[1] < $sector['y2'] / 10 &&
        $sector['lower'] * 100 <= $p[2] && $p[2] < $sector['upper'] * 100;
}

function classify_conflicts(&$conflicts, $sectors, $remaining, $resolved, $dh, $final = false)
{
    foreach ($conflicts as &$conflict) {
        $piece = $conflict['closest']; $a = $piece['aSegment']; $b = $piece['bSegment'];
        $pa = position($a, $piece['tc']); $pb = position($b, $piece['tc']); $trackA = track($a); $trackB = track($b);
        $angle = min(abs($trackA - $trackB), 360 - abs($trackA - $trackB));
        $dot = $a['velocity'][0] * $b['velocity'][0] + $a['velocity'][1] * $b['velocity'][1];
        $cross = $a['velocity'][0] * $b['velocity'][1] - $a['velocity'][1] * $b['velocity'][0];
        $geometry = $dot * $dot > $cross * $cross ? ($dot < 0 ? 'head_on' : 'trailing') : 'crossing';
        $severity = 10 * $piece['distance'] < 4 * $dh ? 'HIGH' : (10 * $piece['distance'] < 7 * $dh ? 'MEDIUM' : 'LOW');
        $mid = [($pa[0] + $pb[0]) / 2, ($pa[1] + $pb[1]) / 2, ($pa[2] + $pb[2]) / 2];
        $sector = '-'; foreach ($sectors as $s) if (contains($s, $mid)) { $sector = $s['name']; break; }
        $key = pair_key($conflict['pair']);
        $outcome = $final || isset($remaining[$key]) ? 'remaining' : (isset($resolved[$key]) ? 'resolved' : 'indirect');
        $conflict = array_merge($conflict, ['levelA' => $pa[2] / 100, 'levelB' => $pb[2] / 100, 'trackA' => $trackA, 'trackB' => $trackB,
            'angle' => $angle, 'geometry' => $geometry, 'severity' => $severity, 'sector' => $sector, 'outcome' => $outcome]);
    }
    unset($conflict);
}

function active_conflicts($conflicts, $time)
{
    $result = []; foreach ($conflicts as $c) if ($c['start'] <= $time && $time < $c['end']) $result[] = $c; return $result;
}

function trajectory_rows($trajectories)
{
    $lines = ['callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end'];
    foreach (names($trajectories) as $code) foreach ($trajectories[$code]['segments'] as $s) {
        $lines[] = implode(',', [$code, $s['number'], $s['leg'], $s['phase'], decimal($s['ts']), decimal($s['te']), decimal($s['start'][0]), decimal($s['start'][1]),
            (int) round($s['start'][2] / 100), decimal($s['end'][0]), decimal($s['end'][1]), (int) round($s['end'][2] / 100)]);
    }
    return $lines;
}

function per_flight_conflicts($conflicts)
{
    $result = [];
    foreach ($conflicts as $c) { [$a, $b] = $c['pair']; $result[$a][] = [$c, $b]; $result[$b][] = [$c, $a]; }
    return $result;
}

function conflict_report($label, $conflicts, $trajectories, $params)
{
    $lines = ['CONFLICTS ' . named(['plan' => $label, 'count' => count($conflicts)])];
    $geometries = ['head_on' => 0, 'crossing' => 0, 'trailing' => 0]; $severities = ['HIGH' => 0, 'MEDIUM' => 0, 'LOW' => 0];
    $total = 0.0; $minimum = null;
    foreach ($conflicts as $index => $c) {
        $p = $c['closest']; $geometries[$c['geometry']]++; $severities[$c['severity']]++; $total += $c['end'] - $c['start'];
        if ($minimum === null || $p['distance'] < $minimum) $minimum = $p['distance'];
        $lines[] = 'CONFLICT ' . ($index + 1) . ' ' . $c['name'] . ' ' . named(['start' => decimal($c['start']), 'end' => decimal($c['end']), 'duration' => decimal($c['end'] - $c['start']), 'outcome' => $c['outcome']]);
        $lines[] = '  CPA ' . named(['t' => decimal($p['tc']), 'dist' => decimal($p['distance']), 'vert' => decimal($p['vertical'], 1),
            'levels' => decimal($c['levelA'], 2) . '/' . decimal($c['levelB'], 2), 'tracks' => decimal($c['trackA'], 1) . '/' . decimal($c['trackB'], 1), 'angle' => decimal($c['angle'], 1)]);
        $lines[] = '  TYPE ' . named(['geometry' => $c['geometry'], 'phases' => $p['aSegment']['phase'] . '/' . $p['bSegment']['phase'],
            'segments' => $p['aSegment']['number'] . '/' . $p['bSegment']['number'], 'sector' => $c['sector'], 'severity' => $c['severity']]);
        foreach ($c['pieces'] as $piece) $lines[] = '  PIECE ' . $piece['aSegment']['number'] . '/' . $piece['bSegment']['number'] . ' ' . decimal($piece['lo']) . ' ' . decimal($piece['hi']);
    }
    $lines[] = 'SUMMARY ' . named(['count' => count($conflicts), 'total' => decimal($total), 'min_dist' => $minimum === null ? '-' : decimal($minimum),
        'head_on' => $geometries['head_on'], 'crossing' => $geometries['crossing'], 'trailing' => $geometries['trailing'], 'high' => $severities['HIGH'], 'medium' => $severities['MEDIUM'], 'low' => $severities['LOW']]);
    $grouped = per_flight_conflicts($conflicts);
    foreach (names($grouped) as $code) {
        $starts = []; $partners = [];
        foreach ($grouped[$code] as [$c, $partner]) { $starts[] = $c['start']; $partners[$partner] = true; }
        $partnerNames = names($partners);
        $lines[] = 'FLIGHT ' . $code . ' ' . named(['conflicts' => count($grouped[$code]), 'first' => decimal(min($starts)), 'partners' => implode(',', $partnerNames)]);
    }
    $lines[] = 'TIMELINE ' . named(['from' => $params['sampleStart'], 'to' => $params['sampleEnd'], 'step' => 60]);
    foreach (names($grouped) as $code) {
        $marks = '';
        foreach (samples($params) as $time) {
            if (active_segment($trajectories[$code], $time) === null) { $marks .= '.'; continue; }
            $active = false; foreach ($grouped[$code] as [$c]) if ($c['start'] <= $time && $time < $c['end']) { $active = true; break; }
            $marks .= $active ? 'X' : '-';
        }
        $lines[] = $code . ' ' . $marks;
    }
    return $lines;
}

function resolution_report($initial, $final, $trajectoriesInitial, $trajectoriesFinal, $initialConflicts, $finalConflicts, $rounds, $unresolvedConflicts)
{
    $lines = [];
    foreach ($rounds as $round) {
        $c = $round['target'];
        $lines[] = 'ROUND ' . $round['number'] . ' ' . $c['name'] . ' ' . named(['start' => decimal($c['start']), 'end' => decimal($c['end']), 'dist' => decimal($c['closest']['distance'])]);
        foreach ($round['trials'] as $a) {
            $line = '  TRY ' . $a['flight'] . ' ' . $a['name'] . ' ' . $a['status'];
            if (isset($a['blocker'])) $line .= ' ' . $a['blocker']['name'] . ' start=' . decimal($a['blocker']['start']);
            $lines[] = $line;
        }
        $lines[] = $round['accepted'] !== null ? '  RESULT resolved ' . $round['accepted']['flight'] . ' ' . $round['accepted']['name'] : '  RESULT unresolved';
    }
    $countInitial = []; $countFinal = [];
    foreach ($initialConflicts as $c) foreach ($c['pair'] as $code) $countInitial[$code] = ($countInitial[$code] ?? 0) + 1;
    foreach ($finalConflicts as $c) foreach ($c['pair'] as $code) $countFinal[$code] = ($countFinal[$code] ?? 0) + 1;
    $totalExtra = 0.0; $totalDelay = 0;
    foreach (names($final) as $code) {
        $original = $initial[$code]; $next = $final[$code]; $prior = $trajectoriesInitial[$code]; $current = $trajectoriesFinal[$code];
        $extra = $current['arrival'] - $prior['arrival']; $totalExtra += $extra; $totalDelay += $next['delay'];
        $lines[] = 'FLIGHT ' . $code . ' ' . named(['departure' => $next['departure'] + $next['delay'], 'delay' => $next['delay'], 'level' => signed($next['offset']),
            'speed' => $original['speed'] . '->' . $next['speed'], 'arrival' => decimal($prior['arrival']) . '->' . decimal($current['arrival']),
            'extra' => decimal($extra), 'length' => decimal($current['length']), 'conflicts' => ($countInitial[$code] ?? 0) . '->' . ($countFinal[$code] ?? 0),
            'manoeuvres' => count($next['history']) ? implode(',', $next['history']) : '-']);
    }
    foreach ($unresolvedConflicts as $c) $lines[] = 'UNRESOLVED ' . $c['name'] . ' ' . named(['start' => decimal($c['start']), 'dist' => decimal($c['closest']['distance'])]);
    $trials = 0; $infeasible = 0; $blocked = 0; $acceptedCount = 0; $level = 0; $speed = 0; $delay = 0;
    foreach ($rounds as $round) {
        foreach ($round['trials'] as $a) { $trials++; if ($a['status'] === 'infeasible') $infeasible++; if ($a['status'] === 'blocked') $blocked++; }
        if ($round['accepted'] !== null) {
            $acceptedCount++; $name = $round['accepted']['name'];
            if (str_starts_with($name, 'level_')) $level++;
            elseif ($name === 'speed_down') $speed++;
            elseif (str_starts_with($name, 'delay_')) $delay++;
        }
    }
    $lines[] = 'TOTAL ' . named(['rounds' => count($rounds), 'resolved' => $acceptedCount, 'unresolved' => count($unresolvedConflicts), 'level' => $level,
        'speed' => $speed, 'delay' => $delay, 'total_delay' => $totalDelay, 'total_extra' => decimal($totalExtra), 'trials' => $trials, 'infeasible' => $infeasible, 'blocked' => $blocked]);
    return $lines;
}

function in_sector($segment, $sector)
{
    $limits = [[$sector['x1'] / 10, $sector['x2'] / 10], [$sector['y1'] / 10, $sector['y2'] / 10], [$sector['lower'] * 100, $sector['upper'] * 100]];
    $lo = $segment['ts']; $hi = $segment['te'];
    for ($axis = 0; $axis < 3; $axis++) {
        $p = $segment['start'][$axis]; $v = $segment['velocity'][$axis]; [$lower, $upper] = $limits[$axis];
        if ($v == 0) { if (!($lower <= $p && $p < $upper)) return null; }
        else {
            $r1 = ($lower - $p) / $v; $r2 = ($upper - $p) / $v;
            $lo = max($lo, $segment['ts'] + min($r1, $r2)); $hi = min($hi, $segment['ts'] + max($r1, $r2));
        }
    }
    return $hi - $lo > 1e-6 ? [$lo, $hi] : null;
}

function find_transits($trajectories, $sectors)
{
    $result = [];
    foreach (names($trajectories) as $code) {
        $trips = [];
        foreach ($sectors as $sector) {
            $combined = [];
            foreach ($trajectories[$code]['segments'] as $segment) {
                $range = in_sector($segment, $sector); if ($range === null) continue;
                $last = count($combined) - 1;
                if ($last >= 0 && $range[0] - $combined[$last][1] <= 1e-6) $combined[$last][1] = $range[1];
                else $combined[] = $range;
            }
            foreach ($combined as [$entry, $exit]) $trips[] = ['code' => $code, 'sector' => $sector['name'], 'sectorIndex' => $sector['index'], 'entry' => $entry, 'exit' => $exit, 'from' => '-', 'to' => '-'];
        }
        usort($trips, fn($a, $b) => ($a['entry'] <=> $b['entry']) ?: ($a['sectorIndex'] <=> $b['sectorIndex']));
        for ($i = 1; $i < count($trips); $i++) if (abs($trips[$i]['entry'] - $trips[$i - 1]['exit']) <= 1e-6) {
            $trips[$i - 1]['to'] = $trips[$i]['sector']; $trips[$i]['from'] = $trips[$i - 1]['sector'];
        }
        foreach ($trips as $trip) $result[] = $trip;
    }
    return $result;
}

function transits_rows($transits)
{
    $lines = ['callsign,sector,entry,exit,duration,from,to'];
    foreach ($transits as $t) $lines[] = implode(',', [$t['code'], $t['sector'], decimal($t['entry']), decimal($t['exit']), decimal($t['exit'] - $t['entry']), $t['from'], $t['to']]);
    return $lines;
}

function occupancy($trajectories, $sectors, $times)
{
    $table = [];
    foreach ($sectors as $sector) $table[$sector['name']] = array_fill(0, count($times), 0);
    foreach ($times as $i => $time) foreach (names($trajectories) as $code) {
        $state = current_position($trajectories[$code], $time); if ($state === null) continue;
        foreach ($sectors as $sector) if (contains($sector, $state['point'])) $table[$sector['name']][$i]++;
    }
    return $table;
}

function periods($sectors, $times, $before, $after, $initialTransits, $finalTransits)
{
    $result = [];
    foreach ($sectors as $sector) {
        $name = $sector['name'];
        for ($i = 0; $i < count($times); $i += 5) {
            $start = $times[$i]; $end = $start + 300; $iValues = array_slice($before[$name], $i, 5); $fValues = array_slice($after[$name], $i, 5);
            $peakI = max($iValues); $peakF = max($fValues); $entriesIn = 0; $entriesOut = 0;
            foreach ($initialTransits as $t) if ($t['sector'] === $name && $start <= $t['entry'] && $t['entry'] < $end) $entriesIn++;
            foreach ($finalTransits as $t) if ($t['sector'] === $name && $start <= $t['entry'] && $t['entry'] < $end) $entriesOut++;
            $sum = 0; foreach ($fValues as $v) $sum += $v;
            $result[] = ['name' => $name, 'period' => intdiv($i, 5) + 1, 'start' => $start, 'end' => $end, 'entriesIn' => $entriesIn, 'entriesOut' => $entriesOut,
                'peakI' => $peakI, 'peakF' => $peakF, 'meanF' => $sum / 5, 'capacity' => $sector['capacity'],
                'status' => $peakF > $sector['capacity'] ? 'OVER' : ($peakI > $sector['capacity'] ? 'RELIEVED' : 'OK')];
        }
    }
    return $result;
}

function period_rows($rows)
{
    $lines = ['sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status'];
    foreach ($rows as $row) $lines[] = implode(',', [$row['name'], $row['period'], $row['start'], $row['end'], $row['entriesIn'], $row['entriesOut'],
        $row['peakI'], $row['peakF'], decimal($row['meanF'], 1), $row['capacity'], $row['status']]);
    return $lines;
}

function level_usage($trajectories)
{
    $result = [];
    foreach (names($trajectories) as $code) foreach ($trajectories[$code]['segments'] as $s) {
        if ($s['phase'] !== 'LVL') continue;
        $level = (int) round($s['start'][2] / 100);
        if (!isset($result[$level])) $result[$level] = ['planes' => [], 'time' => 0.0];
        $result[$level]['planes'][$code] = true; $result[$level]['time'] += $s['te'] - $s['ts'];
    }
    return $result;
}

function sector_report($sectors, $times, $initialOcc, $finalOcc, $initialTransits, $finalTransits, $initialConflicts, $finalConflicts, $initialTrajectory, $finalTrajectory)
{
    $result = [];
    foreach ($sectors as $sector) {
        $name = $sector['name'];
        $result[] = 'SECTOR ' . $name . ' x=' . $sector['x1'] . '..' . $sector['x2'] . ' y=' . $sector['y1'] . '..' . $sector['y2'] .
            ' fl=' . $sector['lower'] . '..' . $sector['upper'] . ' capacity=' . $sector['capacity'];
        foreach ([['INITIAL', $initialTransits, $initialOcc, $initialConflicts], ['FINAL', $finalTransits, $finalOcc, $finalConflicts]] as [$label, $transits, $occupation, $conflicts]) {
            $count = 0; $total = 0.0; $over = 0; $conflictCount = 0;
            foreach ($transits as $t) if ($t['sector'] === $name) { $count++; $total += $t['exit'] - $t['entry']; }
            for ($i = 0; $i < count($times); $i += 5) if (max(array_slice($occupation[$name], $i, 5)) > $sector['capacity']) $over++;
            foreach ($conflicts as $c) if ($c['sector'] === $name) $conflictCount++;
            $result[] = $label . ' ' . named(['entries' => $count, 'time' => decimal($total), 'mean' => $count ? decimal($total / $count) : '-',
                'peak' => max($occupation[$name]), 'over' => $over, 'conflicts' => $conflictCount]);
        }
        $values = $finalOcc[$name]; $highest = max($sector['capacity'] + 1, max($values)); $rows = [];
        for ($k = $highest; $k >= 1; $k--) {
            $line = ''; foreach ($values as $v) $line .= $v >= $k ? '#' : ($k === $sector['capacity'] ? '-' : '.');
            $rows[] = $line;
        }
        append_lines($result, chart($rows));
    }
    $before = level_usage($initialTrajectory); $after = level_usage($finalTrajectory);
    $levels = array_values(array_unique(array_merge(array_keys($before), array_keys($after)))); rsort($levels, SORT_NUMERIC);
    $result[] = 'LEVELS';
    foreach ($levels as $level) {
        $b = $before[$level] ?? ['planes' => [], 'time' => 0.0]; $a = $after[$level] ?? ['planes' => [], 'time' => 0.0];
        $result[] = 'LEVEL ' . $level . ' ' . named(['flights' => count($b['planes']) . '->' . count($a['planes']), 'time' => decimal($b['time']) . '->' . decimal($a['time'])]);
    }
    $counts = []; $sectorOrder = [];
    foreach ($sectors as $s) $sectorOrder[$s['name']] = $s['index'];
    foreach ($finalTransits as $t) if ($t['to'] !== '-') {
        $key = $t['sector'] . '/' . $t['to']; $counts[$key] = ($counts[$key] ?? 0) + 1;
    }
    $total = 0; foreach ($counts as $count) $total += $count;
    $result[] = 'HANDOFFS plan=final count=' . $total;
    $keys = array_keys($counts);
    usort($keys, function ($a, $b) use ($sectorOrder) {
        [$a1, $a2] = explode('/', $a); [$b1, $b2] = explode('/', $b);
        return ($sectorOrder[$a1] <=> $sectorOrder[$b1]) ?: ($sectorOrder[$a2] <=> $sectorOrder[$b2]);
    });
    foreach ($keys as $key) { [$first, $second] = explode('/', $key); $result[] = 'HANDOFF ' . $first . ' ' . $second . ' ' . $counts[$key]; }
    return $result;
}

function alerts($trajectories, $conflicts, $params)
{
    $observations = [];
    foreach (samples($params) as $time) {
        $current = [];
        foreach (names($trajectories) as $code) {
            $value = current_position($trajectories[$code], $time);
            if ($value !== null) $current[$code] = $value;
        }
        $flying = names($current);
        for ($i = 0; $i < count($flying); $i++) for ($j = $i + 1; $j < count($flying); $j++) {
            $a = $current[$flying[$i]]; $b = $current[$flying[$j]]; $relative = []; $velocity = [];
            for ($k = 0; $k < 3; $k++) { $relative[] = $a['point'][$k] - $b['point'][$k]; $velocity[] = $a['segment']['velocity'][$k] - $b['segment']['velocity'][$k]; }
            $loss = loss_interval($relative, $velocity, 0, $params['alert'], $params['dh'], $params['dv']);
            if ($loss === null) continue;
            $pair = $flying[$i] . '-' . $flying[$j];
            $observations[$pair][] = ['time' => $time, 'loss' => $time + $loss['lo'], 'distance' => $loss['distance']];
        }
    }
    $found = [];
    foreach ($observations as $pair => $records) {
        $grouped = [];
        foreach ($records as $record) {
            $last = count($grouped) - 1;
            if ($last >= 0 && $record['time'] - $grouped[$last][count($grouped[$last]) - 1]['time'] === 60) $grouped[$last][] = $record;
            else $grouped[] = [$record];
        }
        foreach ($grouped as $group) {
            $minimum = null; foreach ($group as $record) if ($minimum === null || $record['distance'] < $minimum) $minimum = $record['distance'];
            $found[] = ['pair' => $pair, 'first' => $group[0]['time'], 'last' => $group[count($group) - 1]['time'], 'samples' => count($group),
                'predicted' => $group[0]['loss'], 'minDist' => $minimum];
        }
    }
    usort($found, fn($a, $b) => ($a['first'] <=> $b['first']) ?: strcmp($a['pair'], $b['pair']));
    $detected = [];
    foreach ($found as &$item) {
        $indices = [];
        foreach ($conflicts as $i => $c) if ($c['name'] === $item['pair'] && $c['start'] < $item['last'] + $params['alert'] && $c['end'] > $item['first']) {
            $indices[] = $i; $detected[$i] = true;
        }
        $item['lead'] = count($indices) ? $conflicts[$indices[0]]['start'] - $item['first'] : null;
    }
    unset($item);
    $missed = []; foreach ($conflicts as $i => $c) if (!isset($detected[$i])) $missed[] = $c;
    return compact('found', 'missed');
}

function alert_report($label, $trajectories, $conflicts, $params)
{
    $result = alerts($trajectories, $conflicts, $params); $found = $result['found']; $missed = $result['missed'];
    $lines = ['ALERTS ' . named(['plan' => $label, 'horizon' => $params['alert'], 'count' => count($found)])]; $leads = [];
    foreach ($found as $i => $a) {
        if ($a['lead'] !== null) $leads[] = $a['lead'];
        $lines[] = 'ALERT ' . ($i + 1) . ' ' . $a['pair'] . ' ' . named(['first' => $a['first'], 'last' => $a['last'], 'samples' => $a['samples'],
            'predicted' => decimal($a['predicted']), 'min_dist' => decimal($a['minDist']), 'status' => $a['lead'] === null ? 'false' : 'true', 'lead' => $a['lead'] === null ? '-' : decimal($a['lead'])]);
    }
    foreach ($missed as $c) $lines[] = 'MISSED ' . $c['name'] . ' ' . named(['start' => decimal($c['start']), 'end' => decimal($c['end'])]);
    $total = 0.0; foreach ($leads as $lead) $total += $lead;
    $lines[] = 'SUMMARY ' . named(['alerts' => count($found), 'true' => count($leads), 'false' => count($found) - count($leads), 'missed' => count($missed), 'mean_lead' => count($leads) ? decimal($total / count($leads)) : '-']);
    return $lines;
}

function radar_cell($point, $params)
{
    [$rx0, $ry0, $rx1, $ry1, $width, $height] = $params['radar'];
    $col = (int) floor((10 * $point[0] - $rx0) * $width / ($rx1 - $rx0));
    $bottom = (int) floor((10 * $point[1] - $ry0) * $height / ($ry1 - $ry0));
    return 0 <= $col && $col < $width && 0 <= $bottom && $bottom < $height ? [$col, $height - 1 - $bottom] : null;
}

function radar_snapshot($label, $trajectories, $conflicts, $time, $params)
{
    $width = $params['radar'][4]; $height = $params['radar'][5];
    $grid = array_fill(0, $height, array_fill(0, $width, '.')); $current = []; $locations = [];
    foreach (names($trajectories) as $code) {
        $state = current_position($trajectories[$code], $time); if ($state === null) continue;
        $cell = radar_cell($state['point'], $params); $state['cell'] = $cell; $current[$code] = $state;
        if ($cell !== null) $locations[implode(',', $cell)][] = $code;
    }
    $active = active_conflicts($conflicts, $time); $conflicted = [];
    foreach ($active as $c) foreach ($c['pair'] as $code) $conflicted[$code] = true;
    foreach ($locations as $key => $flightNames) {
        [$col, $row] = array_map('intval', explode(',', $key)); $one = $flightNames[0];
        $grid[$row][$col] = count($flightNames) > 1 ? (string) count($flightNames) : (isset($conflicted[$one]) ? strtolower($one[0]) : $one[0]);
    }
    foreach (names($current) as $code) {
        $forecast = current_position($trajectories[$code], $time + $params['leader']); if ($forecast === null) continue;
        $cell = radar_cell($forecast['point'], $params);
        if ($cell !== null && $grid[$cell[1]][$cell[0]] === '.') $grid[$cell[1]][$cell[0]] = '*';
    }
    $lines = ['RADAR ' . named(['plan' => $label, 't' => $time, 'aircraft' => count($current), 'conflicts' => count($active)])];
    $rows = []; foreach ($grid as $row) $rows[] = implode('', $row); append_lines($lines, chart($rows));
    foreach (names($current) as $code) {
        $record = $current[$code]; [$x, $y, $z] = $record['point'];
        $lines[] = $code . ' ' . named(['x' => decimal($x), 'y' => decimal($y), 'fl' => decimal($z / 100, 2), 'track' => decimal(track($record['segment']), 1),
            'phase' => $record['segment']['phase'], 'cell' => $record['cell'] !== null ? implode(',', $record['cell']) : 'outside']);
    }
    foreach ($active as $conflict) {
        $a = $current[$conflict['pair'][0]]['point']; $b = $current[$conflict['pair'][1]]['point'];
        $dx = $a[0] - $b[0]; $dy = $a[1] - $b[1];
        $lines[] = 'CONFLICT ' . $conflict['name'] . ' ' . named(['dist' => decimal(sqrt($dx * $dx + $dy * $dy)), 'vert' => decimal(abs($a[2] - $b[2]), 1)]);
    }
    return $lines;
}

function density_report($label, $trajectories, $params)
{
    $width = $params['radar'][4]; $height = $params['radar'][5]; $density = array_fill(0, $height, array_fill(0, $width, 0));
    foreach (samples($params) as $time) foreach (names($trajectories) as $code) {
        $state = current_position($trajectories[$code], $time); if ($state === null) continue;
        $cell = radar_cell($state['point'], $params); if ($cell !== null) $density[$cell[1]][$cell[0]]++;
    }
    $biggest = 0; $rows = [];
    foreach ($density as $row) {
        $line = '';
        foreach ($row as $value) { $biggest = max($biggest, $value); $line .= $value === 0 ? '.' : ($value <= 9 ? (string) $value : '#'); }
        $rows[] = $line;
    }
    $lines = ['DENSITY ' . named(['plan' => $label, 'from' => $params['sampleStart'], 'to' => $params['sampleEnd'], 'step' => 60, 'max' => $biggest])];
    return array_merge($lines, chart($rows));
}

function strips($initial, $final, $first, $last, $transits)
{
    $lines = [];
    foreach (names($final) as $code) {
        $plan = $final[$code]; $before = $first[$code]; $after = $last[$code];
        $lines[] = 'STRIP ' . $code . ' ' . named(['type' => $plan['type'], 'waypoints' => count($plan['waypoints']), 'length' => decimal($after['length']),
            'manoeuvres' => count($plan['history']) ? implode(',', $plan['history']) : '-']);
        foreach ($plan['waypoints'] as $index => $waypoint) {
            $original = $before['waypointTimes'][$index]; $current = $after['waypointTimes'][$index];
            $lines[] = 'WPT ' . $index . ' ' . named(['at' => $waypoint['x'] . ':' . $waypoint['y'], 'eta' => decimal($original[0]) . '->' . decimal($current[0]),
                'fl' => $original[1] . '->' . $current[1]]);
        }
        $order = [];
        foreach ($transits as $t) if ($t['code'] === $code) $order[] = $t['sector'] . '@' . decimal($t['entry']);
        $lines[] = 'SECTORS ' . (count($order) ? implode(',', $order) : '-');
    }
    return $lines;
}

function main()
{
    $input = load_all(); $initial = $input['flights']; $types = $input['types']; $sectors = $input['sectors']; $params = $input['params'];
    $trajectoriesInitial = [];
    foreach ($initial as $code => $plan) $trajectoriesInitial[$code] = build_trajectory($plan, $types);
    $initialConflicts = all_conflicts($trajectoriesInitial, $params['dh'], $params['dv']);
    $solved = resolve_conflicts($initial, $types, $params); $final = $solved['plans']; $trajectoriesFinal = $solved['trajectories'];
    $finalConflicts = all_conflicts($trajectoriesFinal, $params['dh'], $params['dv']); $finalPairs = [];
    foreach ($finalConflicts as $c) $finalPairs[pair_key($c['pair'])] = true;
    classify_conflicts($initialConflicts, $sectors, $finalPairs, $solved['resolved'], $params['dh']);
    classify_conflicts($finalConflicts, $sectors, $finalPairs, $solved['resolved'], $params['dh'], true);
    $transitsInitial = find_transits($trajectoriesInitial, $sectors); $transitsFinal = find_transits($trajectoriesFinal, $sectors);
    $times = samples($params); $occupancyInitial = occupancy($trajectoriesInitial, $sectors, $times); $occupancyFinal = occupancy($trajectoriesFinal, $sectors, $times);
    $load = periods($sectors, $times, $occupancyInitial, $occupancyFinal, $transitsInitial, $transitsFinal);
    write_lines('trajectories.csv', trajectory_rows($trajectoriesFinal));
    write_lines('conflicts.txt', array_merge(conflict_report('initial', $initialConflicts, $trajectoriesInitial, $params), conflict_report('final', $finalConflicts, $trajectoriesFinal, $params)));
    write_lines('resolutions.txt', resolution_report($initial, $final, $trajectoriesInitial, $trajectoriesFinal, $initialConflicts, $finalConflicts, $solved['rounds'], $solved['unresolvedConflicts']));
    write_lines('sector_transits.csv', transits_rows($transitsFinal));
    write_lines('sector_load.csv', period_rows($load));
    write_lines('sector_report.txt', sector_report($sectors, $times, $occupancyInitial, $occupancyFinal, $transitsInitial, $transitsFinal,
        $initialConflicts, $finalConflicts, $trajectoriesInitial, $trajectoriesFinal));
    write_lines('alerts.txt', array_merge(alert_report('initial', $trajectoriesInitial, $initialConflicts, $params), alert_report('final', $trajectoriesFinal, $finalConflicts, $params)));
    $radar = [];
    foreach ($params['snapshots'] as $time) {
        append_lines($radar, radar_snapshot('initial', $trajectoriesInitial, $initialConflicts, $time, $params));
        append_lines($radar, radar_snapshot('final', $trajectoriesFinal, $finalConflicts, $time, $params));
    }
    append_lines($radar, density_report('initial', $trajectoriesInitial, $params));
    append_lines($radar, density_report('final', $trajectoriesFinal, $params));
    write_lines('radar.txt', $radar);
    write_lines('strips.txt', strips($initial, $final, $trajectoriesInitial, $trajectoriesFinal, $transitsFinal));
}

main();
