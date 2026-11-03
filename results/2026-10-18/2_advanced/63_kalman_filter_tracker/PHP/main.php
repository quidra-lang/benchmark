<?php

require_once __DIR__ . '/matrix.php';
require_once __DIR__ . '/kalman.php';
require_once __DIR__ . '/association.php';
require_once __DIR__ . '/imm.php';
require_once __DIR__ . '/evaluation.php';

const FILTERS = ['cv', 'ca', 'abg', 'imm', 'rts'];
const CHARACTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

function sumValues($values)
{
    $total = 0.0;
    foreach ($values as $value) {
        $total += $value;
    }
    return $total;
}

function mean($values)
{
    return sumValues($values) / count($values);
}

function absent($value)
{
    return $value === null ? '-' : (string)$value;
}

function listLine($name, $values)
{
    return $name . ' ' . ($values ? implode(' ', $values) : 'none');
}

function readInputs()
{
    $scans = [];
    $targetMap = [];
    foreach (array_slice(file('input/measurements.csv', FILE_IGNORE_NEW_LINES), 1) as $line) {
        [$scan, $time, $x, $y] = explode(',', $line);
        $k = (int)$scan;
        if (!isset($scans[$k - 1])) {
            $scans[$k - 1] = ['number' => $k, 'time' => (float)$time, 'points' => []];
        }
        $scans[$k - 1]['points'][] = [(float)$x, (float)$y];
    }
    foreach (array_slice(file('input/truth.csv', FILE_IGNORE_NEW_LINES), 1) as $line) {
        [$number, $scan, $x, $y] = explode(',', $line);
        $number = (int)$number;
        $k = (int)$scan;
        if (!isset($targetMap[$number])) {
            $targetMap[$number] = (object)['number' => $number, 'first' => $k, 'last' => $k, 'positions' => [], 'track' => null];
        }
        $targetMap[$number]->positions[$k] = [(float)$x, (float)$y];
        $targetMap[$number]->last = $k;
    }
    ksort($targetMap, SORT_NUMERIC);
    $params = [];
    $arrayNames = ['CONFIRM', 'ABG', 'IMM_Q', 'IMM_TRANSITION', 'IMM_INITIAL', 'NIS_EDGES', 'PLOT_X', 'PLOT_Y', 'PLOT_SIZE'];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $words = explode(' ', $line);
        $key = array_shift($words);
        if ($key === 'MODEL') {
            $params[$key] = $words[0];
        } elseif (in_array($key, $arrayNames, true)) {
            $params[$key] = array_map(in_array($key, ['CONFIRM', 'PLOT_SIZE'], true) ? 'intval' : 'floatval', $words);
        } else {
            $params[$key] = $key === 'DELETE' ? (int)$words[0] : (float)$words[0];
        }
    }
    return [$scans, array_values($targetMap), $params];
}

function greedyAssignment($costs)
{
    $candidates = [];
    foreach ($costs as $i => $row) {
        foreach ($row as $j => $cost) {
            if ($cost !== null) {
                $candidates[] = [$i, $j, $cost];
            }
        }
    }
    usort($candidates, fn($a, $b) => ($a[2] <=> $b[2]) ?: (($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1])));
    $rows = $columns = $pairs = [];
    foreach ($candidates as [$i, $j, $cost]) {
        if (isset($rows[$i]) || isset($columns[$j])) {
            continue;
        }
        $pairs[] = [$i, $j];
        $rows[$i] = $columns[$j] = true;
    }
    usort($pairs, fn($a, $b) => $a[0] <=> $b[0]);
    return $pairs;
}

function runTracking($scans, $params)
{
    $tracks = [];
    $csv = ['track,scan,x,y,vx,vy,status'];
    $log = [];
    $conflictingMeasurements = $conflictingTracks = $greedyDifferences = 0;
    $q = $params['MODEL'] === 'CV' ? $params['Q_CV'] : $params['Q_CA'];
    foreach ($scans as $scan) {
        $k = $scan['number'];
        $live = array_values(array_filter($tracks, fn($track) => $track->status !== 'deleted'));
        if ($k > 1) {
            $t = $scan['time'] - $scans[$k - 2]['time'];
            foreach ($live as $track) {
                $track->estimate = kalmanPredict($track->estimate, $params['MODEL'], $t, $q);
            }
        }
        $innovations = $costs = $gate = [];
        foreach ($live as $i => $track) {
            $innovationRow = $costRow = [];
            foreach ($scan['points'] as $j => $point) {
                $innovation = kalmanInnovation($track->estimate, $point, $params['SIGMA']);
                $innovationRow[] = $innovation;
                $cost = $innovation['d2'] <= $params['GATE'] ? $innovation['d2'] : null;
                $costRow[] = $cost;
                if ($cost !== null) {
                    $gate[] = $track->number . ':' . ($j + 1) . '=' . fixed($cost);
                }
            }
            $innovations[] = $innovationRow;
            $costs[] = $costRow;
        }
        $rowConflicts = $columnConflicts = 0;
        foreach ($costs as $row) {
            if (count(array_filter($row, fn($value) => $value !== null)) >= 2) {
                $rowConflicts++;
            }
        }
        foreach ($scan['points'] as $j => $point) {
            $count = 0;
            foreach ($costs as $row) {
                if ($row[$j] !== null) {
                    $count++;
                }
            }
            if ($count >= 2) {
                $columnConflicts++;
            }
        }
        $conflictingMeasurements += $columnConflicts;
        $conflictingTracks += $rowConflicts;
        $assigned = optimalAssignment($costs);
        $greedy = greedyAssignment($costs);
        if ($assigned !== $greedy) {
            $greedyDifferences++;
        }
        $byTrack = $used = [];
        foreach ($assigned as [$i, $j]) {
            $byTrack[$i] = $j;
            $used[$j] = true;
        }
        $missed = $confirmed = $deleted = $created = $newPairs = [];
        foreach ($live as $i => $track) {
            $measurement = $nis = null;
            if (isset($byTrack[$i])) {
                $j = $byTrack[$i];
                $measurement = $scan['points'][$j];
                $nis = $innovations[$i][$j]['d2'];
                $track->estimate = kalmanUpdate($track->estimate, $innovations[$i][$j]);
                $track->hits++;
                $track->consecutive = 0;
                $track->end = $k;
            } else {
                $track->consecutive++;
                $missed[] = $track->number;
            }
            $track->records[] = ['measurement' => $measurement, 'nis' => $nis];
        }
        foreach ($live as $track) {
            if ($track->status === 'confirmed') {
                if ($track->consecutive >= $params['DELETE']) {
                    $track->status = 'deleted';
                    $track->deletion = $k;
                    $deleted[] = $track->number;
                }
            } elseif ($track->hits >= $params['CONFIRM'][0]) {
                $track->status = 'confirmed';
                $track->confirmation = $k;
                $confirmed[] = $track->number;
            } elseif ($k - $track->birth + 1 >= $params['CONFIRM'][1]) {
                $track->status = 'deleted';
                $track->deletion = $k;
                $deleted[] = $track->number;
            }
        }
        foreach ($scan['points'] as $j => $measurement) {
            if (isset($used[$j])) {
                continue;
            }
            $track = (object)['number' => count($tracks) + 1, 'birth' => $k, 'end' => $k, 'confirmation' => null, 'deletion' => null,
                'status' => 'tentative', 'hits' => 1, 'consecutive' => 0, 'estimate' => kalmanInitialize($params['MODEL'], $measurement, $params),
                'records' => [['measurement' => $measurement, 'nis' => null]]];
            $tracks[] = $track;
            $created[] = $track;
            $newPairs[] = $track->number . ':' . ($j + 1);
        }
        foreach (array_merge($live, $created) as $track) {
            $csv[] = implode(',', array_merge([$track->number, $k], array_map('fixed', array_slice($track->estimate['x'], 0, 4)), [$track->status]));
        }
        $formatPairs = function ($pairs) use ($live) {
            return array_map(fn($pair) => $live[$pair[0]]->number . ':' . ($pair[1] + 1), $pairs);
        };
        $log[] = 'scan ' . $k . ' tracks ' . count($live) . ' measurements ' . count($scan['points']);
        $log[] = listLine('gate', $gate);
        $log[] = listLine('assign', $formatPairs($assigned));
        $log[] = listLine('greedy', $formatPairs($greedy));
        $log[] = listLine('missed', $missed);
        $log[] = listLine('new', $newPairs);
        $log[] = listLine('confirmed', $confirmed);
        $log[] = listLine('deleted', $deleted);
        $tentative = count(array_filter($tracks, fn($track) => $track->status === 'tentative'));
        $confirmedCount = count(array_filter($tracks, fn($track) => $track->status === 'confirmed'));
        $log[] = 'status tentative ' . $tentative . ' confirmed ' . $confirmedCount;
        $log[] = 'conflicts measurements ' . $columnConflicts . ' tracks ' . $rowConflicts;
    }
    return ['tracks' => $tracks, 'csv' => $csv, 'log' => $log, 'conflictingMeasurements' => $conflictingMeasurements,
        'conflictingTracks' => $conflictingTracks, 'greedyDifferences' => $greedyDifferences];
}

function kalmanRun($track, $kind, $scans, $params)
{
    $estimate = kalmanInitialize($kind, $track->sequence[0]['measurement'], $params);
    $history = [['estimate' => $estimate, 'prediction' => null]];
    $states = [array_slice($estimate['x'], 0, 4)];
    $likelihoods = [];
    $q = $kind === 'CV' ? $params['Q_CV'] : $params['Q_CA'];
    for ($i = 1; $i < count($track->sequence); $i++) {
        $k = $track->birth + $i;
        $t = $scans[$k - 1]['time'] - $scans[$k - 2]['time'];
        $prediction = kalmanPredict($estimate, $kind, $t, $q);
        $measurement = $track->sequence[$i]['measurement'];
        if ($measurement === null) {
            $estimate = $prediction;
        } else {
            $estimate = kalmanUpdate($prediction, kalmanInnovation($prediction, $measurement, $params['SIGMA']));
            $likelihoods[] = $estimate['logLikelihood'];
        }
        $history[] = ['estimate' => $estimate, 'prediction' => $prediction];
        $states[] = array_slice($estimate['x'], 0, 4);
    }
    return ['states' => $states, 'history' => $history, 'logLikelihood' => sumValues($likelihoods)];
}

function abgRun($track, $scans, $params)
{
    $state = array_merge($track->sequence[0]['measurement'], [0.0, 0.0, 0.0, 0.0]);
    $states = [array_slice($state, 0, 4)];
    [$alpha, $beta, $gamma] = $params['ABG'];
    for ($i = 1; $i < count($track->sequence); $i++) {
        $k = $track->birth + $i;
        $t = $scans[$k - 1]['time'] - $scans[$k - 2]['time'];
        $predicted = $state;
        $measurement = $track->sequence[$i]['measurement'];
        for ($axis = 0; $axis < 2; $axis++) {
            $predicted[$axis] = $state[$axis] + $t * $state[$axis + 2] + $t * $t * $state[$axis + 4] / 2;
            $predicted[$axis + 2] = $state[$axis + 2] + $t * $state[$axis + 4];
            if ($measurement !== null) {
                $residual = $measurement[$axis] - $predicted[$axis];
                $predicted[$axis] += $alpha * $residual;
                $predicted[$axis + 2] += $beta * $residual / $t;
                $predicted[$axis + 4] += 2 * $gamma * $residual / ($t * $t);
            }
        }
        $state = $predicted;
        $states[] = array_slice($state, 0, 4);
    }
    return ['states' => $states];
}

function immRun($track, $scans, $params)
{
    $state = immInitialize($track->sequence[0]['measurement'], $params);
    $states = [immEstimate($state)];
    $high = [$state['probabilities'][1]];
    for ($i = 1; $i < count($track->sequence); $i++) {
        $k = $track->birth + $i;
        $state = immAdvance($state, $scans[$k - 1]['time'] - $scans[$k - 2]['time'], $track->sequence[$i]['measurement'], $params);
        $states[] = immEstimate($state);
        $high[] = $state['probabilities'][1];
    }
    return ['states' => $states, 'high' => $high];
}

function pathLength($points)
{
    $total = 0.0;
    for ($i = 1; $i < count($points); $i++) {
        $total += distance($points[$i], $points[$i - 1]);
    }
    return $total;
}

function scanSegments($labels, $first)
{
    $segments = [];
    $current = null;
    foreach ($labels as $i => $label) {
        if ($label === null) {
            $current = null;
        } elseif ($current === null || $segments[$current]['target'] !== $label) {
            $segments[] = ['first' => $first + $i, 'last' => $first + $i, 'target' => $label];
            $current = count($segments) - 1;
        } else {
            $segments[$current]['last'] = $first + $i;
        }
    }
    return $segments;
}

function prepareTracks($tracking, $scans, $params)
{
    $tracks = array_values(array_filter($tracking['tracks'], fn($track) => $track->confirmation !== null));
    $primary = strtolower($params['MODEL']);
    foreach ($tracks as $a => $track) {
        $track->character = CHARACTERS[$a];
        $track->sequence = array_slice($track->records, 0, $track->end - $track->birth + 1);
        $track->nis = [];
        $track->hits = $track->misses = $track->longestGap = 0;
        $gap = 0;
        foreach ($track->sequence as $i => $record) {
            if ($record['measurement'] === null) {
                $track->misses++;
                $gap++;
                $track->longestGap = max($track->longestGap, $gap);
            } else {
                $track->hits++;
                $gap = 0;
                if ($i > 0) {
                    $track->nis[] = $record['nis'];
                }
            }
        }
        $track->filters = ['cv' => kalmanRun($track, 'CV', $scans, $params), 'ca' => kalmanRun($track, 'CA', $scans, $params),
            'abg' => abgRun($track, $scans, $params), 'imm' => immRun($track, $scans, $params)];
        $track->filters['rts'] = ['states' => array_map(fn($state) => array_slice($state, 0, 4), kalmanSmooth($track->filters[$primary]['history']))];
        $track->path = pathLength($track->filters['rts']['states']);
        $track->scanTargets = array_fill(0, count($track->sequence), null);
        $track->matching = null;
        $high = $track->filters['imm']['high'];
        $maximum = 0;
        $highLabels = [];
        $count = 0;
        foreach ($high as $i => $value) {
            if ($value > $high[$maximum]) {
                $maximum = $i;
            }
            if ($value > 0.5) {
                $count++;
                $highLabels[] = 1;
            } else {
                $highLabels[] = null;
            }
        }
        $track->high = ['mean' => mean($high), 'maximum' => $high[$maximum], 'scan' => $track->birth + $maximum,
            'count' => $count, 'segments' => scanSegments($highLabels, $track->birth)];
    }
    return $tracks;
}

function prepareTruth($targets, $scans)
{
    foreach ($targets as $target) {
        $target->count = $target->last - $target->first + 1;
        $target->path = pathLength(array_values($target->positions));
        $target->meanSpeed = $target->path / ($scans[$target->last - 1]['time'] - $scans[$target->first - 1]['time']);
        $target->velocities = [];
        for ($k = $target->first + 1; $k < $target->last; $k++) {
            $before = $target->positions[$k - 1];
            $after = $target->positions[$k + 1];
            $t = $scans[$k]['time'] - $scans[$k - 2]['time'];
            $target->velocities[$k] = [($after[0] - $before[0]) / $t, ($after[1] - $before[1]) / $t];
        }
    }
}

function associateScans($tracks, $targets, $scans, $params)
{
    $labels = [];
    foreach (FILTERS as $name) {
        foreach ($targets as $target) {
            $labels[$name][$target->number] = array_fill(0, count($scans), null);
        }
    }
    $table = [];
    $primary = strtolower($params['MODEL']);
    foreach ($scans as $scan) {
        $k = $scan['number'];
        $active = array_values(array_filter($tracks, fn($track) => $track->birth <= $k && $k <= $track->end));
        $existing = array_values(array_filter($targets, fn($target) => isset($target->positions[$k])));
        $truth = array_map(fn($target) => $target->positions[$k], $existing);
        $values = [];
        foreach (FILTERS as $name) {
            $estimates = [];
            $costs = [];
            foreach ($active as $track) {
                $estimate = $track->filters[$name]['states'][$k - $track->birth];
                $estimates[] = $estimate;
                $row = [];
                foreach ($truth as $point) {
                    $d = distance($estimate, $point);
                    $row[] = $d <= $params['MATCH_DISTANCE'] ? $d : null;
                }
                $costs[] = $row;
            }
            foreach (optimalAssignment($costs) as [$a, $b]) {
                $labels[$name][$existing[$b]->number][$k - 1] = $active[$a]->number;
                if ($name === $primary) {
                    $active[$a]->scanTargets[$k - $active[$a]->birth] = $existing[$b]->number;
                }
            }
            $values[] = ospa($estimates, $truth, $params['OSPA_CUTOFF']);
        }
        $table[] = ['scan' => $k, 'targets' => count($existing), 'tracks' => count($active), 'values' => $values];
    }
    foreach ($tracks as $track) {
        $track->matchedScans = count(array_filter($track->scanTargets, fn($value) => $value !== null));
        $track->segments = scanSegments($track->scanTargets, $track->birth);
    }
    $continuity = [];
    foreach (FILTERS as $name) {
        $continuity[$name] = [];
        foreach ($targets as $target) {
            $continuity[$name][] = continuity(array_slice($labels[$name][$target->number], $target->first - 1, $target->last - $target->first + 1));
        }
    }
    return ['labels' => $labels, 'table' => $table, 'continuity' => $continuity];
}

function matchTracks($tracks, $targets, $params)
{
    $primary = strtolower($params['MODEL']);
    $cutoff = $params['OSPA_CUTOFF'];
    $details = $costs = [];
    foreach ($tracks as $track) {
        $detailRow = $costRow = [];
        foreach ($targets as $target) {
            $firstCommon = max($track->birth, $target->first);
            $lastCommon = min($track->end, $target->last);
            if ($firstCommon > $lastCommon) {
                $detailRow[] = null;
                $costRow[] = null;
                continue;
            }
            $first = min($track->birth, $target->first);
            $last = max($track->end, $target->last);
            $total = 0.0;
            $usable = false;
            for ($k = $first; $k <= $last; $k++) {
                if ($firstCommon <= $k && $k <= $lastCommon) {
                    $d = distance($track->filters[$primary]['states'][$k - $track->birth], $target->positions[$k]);
                    $total += min($cutoff, $d);
                    if ($d < $cutoff) {
                        $usable = true;
                    }
                } else {
                    $total += $cutoff;
                }
            }
            $detail = ['cost' => $total / ($last - $first + 1), 'common' => $lastCommon - $firstCommon + 1, 'usable' => $usable];
            $detailRow[] = $detail;
            $costRow[] = $usable ? $detail['cost'] : null;
        }
        $details[] = $detailRow;
        $costs[] = $costRow;
    }
    foreach (optimalAssignment($costs) as [$a, $b]) {
        $tracks[$a]->matching = array_merge($details[$a][$b], ['target' => $targets[$b]]);
        $targets[$b]->track = $tracks[$a];
    }
}

function computeErrors($tracks, $targets, $params)
{
    $overallPosition = $overallVelocity = array_fill(0, count(FILTERS), []);
    $primary = strtolower($params['MODEL']);
    foreach ($targets as $target) {
        if ($target->track === null) {
            continue;
        }
        $track = $target->track;
        $first = max($track->birth, $target->first);
        $last = min($track->end, $target->last);
        $common = range($first, $last);
        $velocityScans = array_values(array_filter($common, fn($k) => isset($target->velocities[$k])));
        $position = $velocity = [];
        foreach (FILTERS as $index => $name) {
            $states = $track->filters[$name]['states'];
            $positionErrors = $velocityErrors = [];
            foreach ($common as $k) {
                $estimate = $states[$k - $track->birth];
                $truth = $target->positions[$k];
                $x = $estimate[0] - $truth[0];
                $y = $estimate[1] - $truth[1];
                $positionErrors[] = $x * $x + $y * $y;
            }
            foreach ($velocityScans as $k) {
                $estimate = $states[$k - $track->birth];
                $truth = $target->velocities[$k];
                $x = $estimate[2] - $truth[0];
                $y = $estimate[3] - $truth[1];
                $velocityErrors[] = $x * $x + $y * $y;
            }
            $position[] = sqrt(mean($positionErrors));
            $velocity[] = sqrt(mean($velocityErrors));
            $overallPosition[$index] = array_merge($overallPosition[$index], $positionErrors);
            $overallVelocity[$index] = array_merge($overallVelocity[$index], $velocityErrors);
        }
        $nees = [];
        foreach ($common as $k) {
            $estimate = $track->filters[$primary]['history'][$k - $track->birth]['estimate'];
            $truth = $target->positions[$k];
            $error = [$estimate['x'][0] - $truth[0], $estimate['x'][1] - $truth[1]];
            $covariance = [array_slice($estimate['P'][0], 0, 2), array_slice($estimate['P'][1], 0, 2)];
            $nees[] = quadratic2($error, matInverse($covariance));
        }
        $target->errors = ['common' => count($common), 'velocityCount' => count($velocityScans),
            'position' => $position, 'velocity' => $velocity, 'nees' => $nees];
    }
    return ['position' => array_map(fn($values) => sqrt(mean($values)), $overallPosition),
        'velocity' => array_map(fn($values) => sqrt(mean($values)), $overallVelocity)];
}

function nisHistogram($tracks, $edges)
{
    $values = [];
    foreach ($tracks as $track) {
        foreach ($track->nis as $value) {
            $values[] = $value;
        }
    }
    $observed = array_fill(0, count($edges) + 1, 0);
    foreach ($values as $value) {
        $bin = 0;
        while ($bin < count($edges) && $value >= $edges[$bin]) {
            $bin++;
        }
        $observed[$bin]++;
    }
    $lower = array_merge([0.0], $edges);
    $expected = [];
    foreach ($lower as $i => $value) {
        $expected[] = count($values) * (exp(-$value / 2) - ($i === count($edges) ? 0 : exp(-$edges[$i] / 2)));
    }
    return ['total' => count($values), 'observed' => $observed, 'expected' => $expected];
}

function rmseText($values)
{
    $rounded = array_map(fn($value) => (float)fixed($value), $values);
    $best = 0;
    for ($i = 1; $i < count($values); $i++) {
        if ($rounded[$i] < $rounded[$best]) {
            $best = $i;
        }
    }
    $fields = [];
    foreach (FILTERS as $i => $name) {
        $fields[] = $name . ' ' . fixed($values[$i]);
    }
    return implode(' ', $fields) . ' best ' . FILTERS[$best];
}

function evaluationLines($scans, $targets, $tracks, $tracking, $perScan, $errors, $params)
{
    $measurementCount = 0;
    foreach ($scans as $scan) {
        $measurementCount += count($scan['points']);
    }
    $falseTracks = count(array_filter($tracks, fn($track) => $track->matchedScans === 0));
    $lostTargets = count(array_filter($targets, fn($target) => $target->track === null));
    $used = 0;
    foreach ($tracks as $track) {
        $used += $track->hits;
    }
    $summary = ['summary', 'scans ' . count($scans), 'measurements ' . $measurementCount, 'targets ' . count($targets),
        'tracks_created ' . count($tracking['tracks']), 'tracks_confirmed ' . count($tracks), 'false_tracks ' . $falseTracks,
        'missed_targets ' . $lostTargets, 'measurements_used ' . $used, 'conflict_measurements ' . $tracking['conflictingMeasurements'],
        'conflict_tracks ' . $tracking['conflictingTracks'], 'greedy_differences ' . $tracking['greedyDifferences']];
    $targetLines = ['targets'];
    foreach ($targets as $target) {
        $targetLines[] = 'target ' . $target->number . ' first ' . $target->first . ' last ' . $target->last . ' scans ' . $target->count .
            ' path ' . fixed($target->path) . ' mean_speed ' . fixed($target->meanSpeed);
    }
    $trackLines = ['tracks'];
    $matching = ['matching'];
    $models = ['models'];
    $high = ['imm'];
    foreach ($tracks as $track) {
        $inside = count(array_filter($track->nis, fn($value) => $value <= $params['CONSISTENCY_BOUND']));
        $trackLines[] = 'track ' . $track->number . ' birth ' . $track->birth . ' confirmed ' . $track->confirmation .
            ' end ' . $track->end . ' deleted ' . absent($track->deletion) . ' hits ' . $track->hits . ' misses ' . $track->misses .
            ' longest_gap ' . $track->longestGap . ' path ' . fixed($track->path) . ' nis ' . fixed(mean($track->nis)) .
            ' nis_inside ' . $inside . '/' . count($track->nis);
        $match = $track->matching === null ? '-' : $track->matching['target']->number . ' common ' . $track->matching['common'] .
            ' mean_distance ' . fixed($track->matching['cost']);
        $segments = array_map(fn($segment) => $segment['first'] . '-' . $segment['last'] . ':' . $segment['target'], $track->segments);
        $matching[] = 'track ' . $track->number . ' target ' . $match . ' matched_scans ' . $track->matchedScans . ' ' . listLine('segments', $segments);
        $cv = $track->filters['cv']['logLikelihood'];
        $ca = $track->filters['ca']['logLikelihood'];
        $models[] = 'track ' . $track->number . ' updates ' . count($track->nis) . ' cv ' . fixed($cv) . ' ca ' . fixed($ca) . ' better ' . ($cv >= $ca ? 'cv' : 'ca');
        $segments = array_map(fn($segment) => $segment['first'] . '-' . $segment['last'], $track->high['segments']);
        $high[] = 'track ' . $track->number . ' mean_high ' . fixed($track->high['mean']) . ' max_high ' . fixed($track->high['maximum']) .
            ' at ' . $track->high['scan'] . ' high_scans ' . $track->high['count'] . ' ' . listLine('segments', $segments);
    }
    $rmse = ['rmse'];
    $consistency = ['consistency'];
    foreach ($targets as $target) {
        $prefix = 'target ' . $target->number;
        if ($target->track === null) {
            $rmse[] = $prefix . ' track -';
            $consistency[] = $prefix . ' track -';
            continue;
        }
        $error = $target->errors;
        $rmse[] = $prefix . ' track ' . $target->track->number . ' common ' . $error['common'] . ' ' . rmseText($error['position']);
        $rmse[] = $prefix . ' velocity ' . $error['velocityCount'] . ' ' . rmseText($error['velocity']);
        $inside = count(array_filter($error['nees'], fn($value) => $value <= $params['CONSISTENCY_BOUND']));
        $consistency[] = $prefix . ' track ' . $target->track->number . ' nees ' . fixed(mean($error['nees'])) . ' inside ' . $inside . '/' . $error['common'];
    }
    $rmse[] = 'overall position ' . rmseText($errors['position']);
    $rmse[] = 'overall velocity ' . rmseText($errors['velocity']);
    $histogram = nisHistogram($tracks, $params['NIS_EDGES']);
    $consistency[] = 'nis_histogram total ' . $histogram['total'] . ' observed ' . implode(' ', $histogram['observed']) .
        ' expected ' . implode(' ', array_map('fixed', $histogram['expected']));
    $ospa = ['ospa cutoff ' . fixed($params['OSPA_CUTOFF']) . ' order 2', 'scan targets tracks cv ca abg imm rts'];
    foreach ($perScan['table'] as $row) {
        $ospa[] = implode(' ', array_merge([$row['scan'], $row['targets'], $row['tracks']], array_map('fixed', $row['values'])));
    }
    $means = [];
    foreach (FILTERS as $i => $name) {
        $values = array_map(fn($row) => $row['values'][$i], $perScan['table']);
        $means[] = fixed(mean($values));
    }
    $ospa[] = 'mean ' . implode(' ', $means);
    $continuityLines = ['continuity'];
    foreach (FILTERS as $name) {
        $records = $perScan['continuity'][$name];
        $covered = $breaks = $swaps = 0;
        foreach ($records as $record) {
            $covered += $record['covered'];
            $breaks += $record['breaks'];
            $swaps += $record['swaps'];
        }
        $continuityLines[] = $name . ' covered ' . $covered . ' breaks ' . $breaks . ' swaps ' . $swaps;
        foreach ($targets as $i => $target) {
            $record = $records[$i];
            $continuityLines[] = '  target ' . $target->number . ' scans ' . $target->count . ' covered ' . $record['covered'] .
                ' breaks ' . $record['breaks'] . ' swaps ' . $record['swaps'] . ' delay ' . absent($record['delay']);
        }
    }
    $sections = [$summary, $targetLines, $trackLines, $matching, $rmse, $consistency, $models, $ospa, $continuityLines, $high];
    $lines = [];
    foreach ($sections as $index => $section) {
        if ($index > 0) {
            $lines[] = '';
        }
        foreach ($section as $line) {
            $lines[] = $line;
        }
    }
    return $lines;
}

function frame($rows)
{
    $border = '+' . str_repeat('-', count($rows[0])) . '+';
    $result = [$border];
    foreach ($rows as $row) {
        $result[] = '|' . implode('', $row) . '|';
    }
    $result[] = $border;
    return $result;
}

function plotLines($scans, $targets, $tracks, $perScan, $params)
{
    [$width, $height] = $params['PLOT_SIZE'];
    [$xmin, $xmax] = $params['PLOT_X'];
    [$ymin, $ymax] = $params['PLOT_Y'];
    $dx = ($xmax - $xmin) / $width;
    $dy = ($ymax - $ymin) / $height;
    $trajectory = array_fill(0, $height, array_fill(0, $width, ' '));
    $measurements = array_fill(0, $height, array_fill(0, $width, 0));
    $cell = function ($point) use ($xmin, $ymax, $dx, $dy, $width, $height) {
        $c = (int)floor(($point[0] - $xmin) / $dx);
        $r = (int)floor(($ymax - $point[1]) / $dy);
        return 0 <= $c && $c < $width && 0 <= $r && $r < $height ? [$r, $c] : null;
    };
    foreach ($targets as $target) {
        foreach ($target->positions as $point) {
            $at = $cell($point);
            if ($at !== null) {
                $trajectory[$at[0]][$at[1]] = '.';
            }
        }
    }
    foreach ($tracks as $track) {
        foreach ($track->filters['rts']['states'] as $state) {
            $at = $cell($state);
            if ($at !== null) {
                $trajectory[$at[0]][$at[1]] = $track->character;
            }
        }
    }
    foreach ($scans as $scan) {
        foreach ($scan['points'] as $point) {
            $at = $cell($point);
            if ($at !== null) {
                $measurements[$at[0]][$at[1]]++;
            }
        }
    }
    $lines = array_merge(['tracks x ' . fixed($xmin) . ' ' . fixed($xmax) . ' y ' . fixed($ymin) . ' ' . fixed($ymax) .
        ' size ' . $width . ' ' . $height], frame($trajectory));
    foreach ($tracks as $track) {
        $lines[] = $track->character . ' track ' . $track->number . ' target ' .
            ($track->matching === null ? '-' : $track->matching['target']->number);
    }
    $measurementRows = [];
    foreach ($measurements as $row) {
        $measurementRows[] = array_map(fn($value) => $value === 0 ? ' ' : ($value < 10 ? (string)$value : '#'), $row);
    }
    $lines[] = '';
    $lines[] = 'measurements';
    foreach (frame($measurementRows) as $line) {
        $lines[] = $line;
    }
    $lines[] = '';
    $lines[] = 'timeline';
    $primary = strtolower($params['MODEL']);
    $characters = [];
    foreach ($tracks as $track) {
        $characters[$track->number] = $track->character;
    }
    foreach ($targets as $target) {
        $labels = $perScan['labels'][$primary][$target->number];
        $timeline = '';
        foreach ($scans as $scan) {
            $k = $scan['number'];
            $timeline .= !isset($target->positions[$k]) ? ' ' :
                ($labels[$k - 1] === null ? '.' : $characters[$labels[$k - 1]]);
        }
        $lines[] = $target->number . ' |' . $timeline . '|';
    }
    $primaryIndex = array_search($primary, FILTERS, true);
    $heights = [];
    foreach ($perScan['table'] as $row) {
        $heights[] = (int)floor(10 * $row['values'][$primaryIndex] / $params['OSPA_CUTOFF']);
    }
    $ospaRows = [];
    for ($row = 0; $row < 10; $row++) {
        $ospaRows[] = array_map(fn($value) => $value >= 10 - $row ? '#' : ' ', $heights);
    }
    $lines[] = '';
    $lines[] = 'ospa ' . $primary;
    foreach (frame($ospaRows) as $line) {
        $lines[] = $line;
    }
    return $lines;
}

function main()
{
    [$scans, $targets, $params] = readInputs();
    $tracking = runTracking($scans, $params);
    $tracks = prepareTracks($tracking, $scans, $params);
    prepareTruth($targets, $scans);
    $perScan = associateScans($tracks, $targets, $scans, $params);
    matchTracks($tracks, $targets, $params);
    $errors = computeErrors($tracks, $targets, $params);
    $smoothed = ['track,scan,x,y,vx,vy'];
    foreach ($tracks as $track) {
        foreach ($track->filters['rts']['states'] as $i => $state) {
            $smoothed[] = implode(',', array_merge([$track->number, $track->birth + $i], array_map('fixed', $state)));
        }
    }
    $files = ['tracks.csv' => $tracking['csv'], 'smoothed.csv' => $smoothed, 'association_log.txt' => $tracking['log'],
        'evaluation.txt' => evaluationLines($scans, $targets, $tracks, $tracking, $perScan, $errors, $params),
        'track_plot.txt' => plotLines($scans, $targets, $tracks, $perScan, $params)];
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    foreach ($files as $name => $lines) {
        file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
    }
}

main();
