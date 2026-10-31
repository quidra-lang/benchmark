<?php

require_once __DIR__ . '/model_io.php';
require_once __DIR__ . '/inference.php';
require_once __DIR__ . '/training.php';
require_once __DIR__ . '/evaluation.php';
require_once __DIR__ . '/sampler.php';

const MODEL_NAMES = ['INITIAL', 'BAUM_WELCH', 'VITERBI_TRAINING', 'SUPERVISED'];
const DECODERS = ['VITERBI', 'POSTERIOR'];

function fields(...$values)
{
    return implode(' ', $values);
}

function parameters($rows, $model)
{
    $values = [];
    foreach ($rows as $row) $values[$row[0]] = array_slice($row, 1);
    $result = [];
    foreach (['iterations', 'folds', 'min_sequence_length', 'max_missing_percent', 'merge_gap', 'min_segment_length',
        'min_rich_percent', 'min_motif_percent', 'boundary_tolerance', 'posterior_seed', 'posterior_samples', 'sample_seed', 'sample_count', 'sample_length'] as $key) {
        $result[$key] = (int) $values[$key][0];
    }
    foreach (['pseudocount', 'confidence'] as $key) $result[$key] = (float) $values[$key][0];
    $result['smoothing'] = [];
    foreach ($values['smoothing'] as $text) $result['smoothing'][] = ['text' => $text, 'value' => (float) $text];
    $result['segment_state'] = array_search($values['segment_state'][0], $model['states'], true);
    $result['motif'] = [];
    foreach ($values['motif'] as $symbol) $result['motif'][] = array_search($symbol, $model['symbols'], true);
    $result['rich_symbols'] = [];
    foreach ($values['rich_symbols'] as $symbol) $result['rich_symbols'][array_search($symbol, $model['symbols'], true)] = true;
    return $result;
}

function rejection_reason(&$record, &$seen, $model, $params, $labeled)
{
    $duplicate = isset($seen[$record['name']]);
    $seen[$record['name']] = true;
    if ($duplicate) return 'duplicate name';
    $record['text'] = strtoupper($record['text']);
    for ($t = 0; $t < strlen($record['text']); $t++) {
        $character = $record['text'][$t];
        if ($character !== $model['missing'] && !in_array($character, $model['symbols'], true)) return fields('invalid symbol', $character, 'at position', $t + 1);
    }
    if ($labeled) {
        for ($t = 0; $t < strlen($record['labels']); $t++) {
            if (!in_array($record['labels'][$t], $model['states'], true)) return fields('invalid label', $record['labels'][$t], 'at position', $t + 1);
        }
        if (strlen($record['text']) !== strlen($record['labels'])) return fields('length mismatch', strlen($record['text']), strlen($record['labels']));
    }
    if (strlen($record['text']) < $params['min_sequence_length']) return 'too short ' . strlen($record['text']);
    $missing = 0;
    foreach (str_split($record['text']) as $character) if ($character === $model['missing']) $missing++;
    if (100 * $missing > $params['max_missing_percent'] * strlen($record['text'])) return 'too many missing ' . $missing;
    $record['missing'] = $missing;
    $record['observations'] = [];
    foreach (str_split($record['text']) as $character) {
        $index = array_search($character, $model['symbols'], true);
        $record['observations'][] = $index === false ? -1 : $index;
    }
    if ($labeled) {
        $record['path'] = [];
        foreach (str_split($record['labels']) as $character) $record['path'][] = array_search($character, $model['states'], true);
    }
    return null;
}

function validate_input($input, $params)
{
    $data = ['unlabeled' => [], 'train' => [], 'test' => [], 'rejected' => []];
    $seen = [];
    foreach ($input['sequences'] as $i => $row) {
        $record = ['name' => $row[0], 'text' => $row[1]];
        $reason = rejection_reason($record, $seen, $input['model'], $params, false);
        if ($reason === null) $data['unlabeled'][] = $record;
        else $data['rejected'][] = ['file' => 'sequences.txt', 'line' => $i + 1, 'name' => $record['name'], 'reason' => $reason];
    }
    $seen = [];
    for ($i = 0; $i < count($input['labeled']); $i += 2) {
        $row = $input['labeled'][$i];
        $record = ['name' => $row[0], 'role' => $row[1], 'text' => $row[2], 'labels' => $input['labeled'][$i + 1][0]];
        $reason = rejection_reason($record, $seen, $input['model'], $params, true);
        if ($reason === null) $data[$record['role'] === 'TRAIN' ? 'train' : 'test'][] = $record;
        else $data['rejected'][] = ['file' => 'labeled.txt', 'line' => $i + 1, 'name' => $record['name'], 'reason' => $reason];
    }
    return $data;
}

function positions($records)
{
    $count = 0;
    foreach ($records as $record) $count += count($record['observations']);
    return $count;
}

function correct_count($left, $right)
{
    $count = 0;
    foreach ($left as $t => $state) if ($state === $right[$t]) $count++;
    return $count;
}

function maximum_change($previous, $current)
{
    $before = array_merge([$previous['initial']], $previous['transition'], $previous['emission']);
    $after = array_merge([$current['initial']], $current['transition'], $current['emission']);
    $maximum = 0.0;
    foreach ($before as $i => $row) foreach ($row as $j => $value) $maximum = max($maximum, abs($after[$i][$j] - $value));
    return $maximum;
}

function baum_welch($initial, $data, $params)
{
    $observations = array_column($data['unlabeled'], 'observations');
    $heldout = array_column(array_merge($data['train'], $data['test']), 'observations');
    $history = [];
    $lines = ['iteration,loglik,heldout,change,max_change,status'];
    $model = $initial;
    $previous = null;
    $violations = 0;
    $best = 0;
    for ($iteration = 0; $iteration <= $params['iterations']; $iteration++) {
        $loglik = total_loglik($model, $observations);
        $held = total_loglik($model, $heldout);
        $history[] = compact('loglik', 'held');
        if ($held > $history[$best]['held']) $best = $iteration;
        if ($iteration === 0) $lines[] = '0,' . real_number($loglik) . ',' . real_number($held) . ',,,';
        else {
            $before = $history[$iteration - 1]['loglik'];
            $violation = $loglik < $before - 0.000001 * abs($before);
            if ($violation) $violations++;
            $lines[] = implode(',', [$iteration, real_number($loglik), real_number($held), real_number($loglik - $before),
                real_number(maximum_change($previous, $model), 6), $violation ? 'violation' : 'ok']);
        }
        if ($iteration < $params['iterations']) {
            $previous = $model;
            $model = reestimate($model, $observations, $params['pseudocount']);
        }
    }
    return compact('model', 'history', 'lines', 'violations', 'best');
}

function viterbi_training($initial, $records, $params)
{
    $observations = array_column($records, 'observations');
    $lines = ['iteration,logprob,loglik,changed'];
    $model = $initial;
    $decoded = [];
    foreach ($observations as $sequence) $decoded[] = viterbi($model, $sequence);
    $changed = null;
    $iteration = 0;
    while (true) {
        $logprob = 0.0;
        foreach ($decoded as $result) $logprob += $result['logprob'];
        $lines[] = implode(',', [$iteration, real_number($logprob), real_number(total_loglik($model, $observations)), $changed === null ? '' : $changed]);
        if ($changed === 0 || $iteration === $params['iterations']) break;
        $pairs = [];
        foreach ($observations as $i => $sequence) $pairs[] = ['observations' => $sequence, 'path' => $decoded[$i]['path']];
        $model = estimate_by_counting($initial, $pairs, $params['pseudocount'], 'VITERBI_TRAINING');
        $next = [];
        foreach ($observations as $sequence) $next[] = viterbi($model, $sequence);
        $changed = 0;
        foreach ($next as $i => $result) $changed += count($observations[$i]) - correct_count($decoded[$i]['path'], $result['path']);
        $decoded = $next;
        $iteration++;
    }
    return ['model' => $model, 'lines' => $lines, 'iterations' => $iteration, 'converged' => $changed === 0];
}

function supervised_training($initial, $data, $params)
{
    $candidates = [];
    $best = 0;
    foreach ($params['smoothing'] as $smoothing) {
        $matrix = confusion(count($initial['states']));
        $folds = [];
        $correct = 0;
        for ($f = 0; $f < $params['folds']; $f++) {
            $train = [];
            $held = [];
            foreach ($data['train'] as $i => $record) {
                if ($i % $params['folds'] === $f) $held[] = $record;
                else $train[] = $record;
            }
            $model = estimate_by_counting($initial, $train, $smoothing['value'], 'SUPERVISED');
            $foldCorrect = 0;
            foreach ($held as $record) $foldCorrect += accumulate($matrix, $record['path'], viterbi($model, $record['observations'])['path']);
            $folds[] = ['records' => count($held), 'positions' => positions($held), 'correct' => $foldCorrect];
            $correct += $foldCorrect;
        }
        $candidates[] = compact('smoothing', 'matrix', 'folds', 'correct');
        if ($correct > $candidates[$best]['correct']) $best = count($candidates) - 1;
    }
    $selected = $candidates[$best];
    $model = estimate_by_counting($initial, $data['train'], $selected['smoothing']['value'], 'SUPERVISED');
    $learning = [];
    for ($r = 1; $r <= count($data['train']); $r++) {
        $current = estimate_by_counting($initial, array_slice($data['train'], 0, $r), $selected['smoothing']['value'], 'SUPERVISED');
        $correct = 0;
        foreach ($data['test'] as $record) $correct += correct_count($record['path'], viterbi($current, $record['observations'])['path']);
        $learning[] = $correct;
    }
    return compact('model', 'selected', 'candidates', 'learning');
}

function segments($path, $params)
{
    $merged = [];
    foreach (runs($path) as $run) {
        if ($run['state'] !== $params['segment_state']) continue;
        $last = count($merged) - 1;
        if ($last >= 0 && $run['start'] - $merged[$last]['end'] - 1 <= $params['merge_gap']) $merged[$last]['end'] = $run['end'];
        else $merged[] = ['start' => $run['start'], 'end' => $run['end']];
    }
    $result = [];
    foreach ($merged as $segment) if ($segment['end'] - $segment['start'] + 1 >= $params['min_segment_length']) $result[] = $segment;
    return $result;
}

function composition($observations, $segment, $params)
{
    $observed = 0;
    $rich = 0;
    $pairs = 0;
    $first = 0;
    $second = 0;
    for ($t = $segment['start']; $t <= $segment['end']; $t++) {
        $symbol = $observations[$t];
        if ($symbol >= 0) {
            $observed++;
            if (isset($params['rich_symbols'][$symbol])) $rich++;
            if ($symbol === $params['motif'][0]) $first++;
            if ($symbol === $params['motif'][1]) $second++;
        }
        if ($t < $segment['end'] && $symbol === $params['motif'][0] && $observations[$t + 1] === $params['motif'][1]) $pairs++;
    }
    $product = $first * $second;
    $island = $product > 0 && 100 * $rich >= $params['min_rich_percent'] * $observed
        && 100 * $pairs * $observed >= $params['min_motif_percent'] * $product;
    return ['rich' => $observed === 0 ? null : $rich / $observed, 'ratio' => $product === 0 ? null : $pairs * $observed / $product, 'island' => $island];
}

function any_overlap($segment, $others)
{
    foreach ($others as $other) if (overlaps($segment, $other)) return true;
    return false;
}

function evaluation_block($model, $records, $decoded, $decoder, $params)
{
    $matrix = confusion(count($model['states']));
    $region = ['predicted' => 0, 'truth' => 0, 'matchedPredicted' => 0, 'matchedTruth' => 0];
    $boundary = ['predicted' => 0, 'truth' => 0, 'matchedPredicted' => 0, 'matchedTruth' => 0];
    $bins = array_fill(0, 10, ['positions' => 0, 'correct' => 0]);
    $recordLines = [];
    $correct = 0;
    foreach ($records as $i => $record) {
        $result = $decoded[$i];
        $path = $decoder === 'VITERBI' ? $result['viterbi'] : $result['posterior'];
        $count = accumulate($matrix, $record['path'], $path);
        $correct += $count;
        $recordLines[] = fields('RECORD', $record['name'], 'length', count($path), 'correct', $count);
        $predicted = segments($path, $params);
        $truth = [];
        foreach (runs($record['path']) as $run) if ($run['state'] === $params['segment_state']) $truth[] = $run;
        $region['predicted'] += count($predicted);
        $region['truth'] += count($truth);
        foreach ($predicted as $segment) if (any_overlap($segment, $truth)) $region['matchedPredicted']++;
        foreach ($truth as $segment) if (any_overlap($segment, $predicted)) $region['matchedTruth']++;
        $predictedBoundaries = boundaries($path);
        $trueBoundaries = boundaries($record['path']);
        $boundary['predicted'] += count($predictedBoundaries);
        $boundary['truth'] += count($trueBoundaries);
        $boundary['matchedPredicted'] += matched_boundaries($predictedBoundaries, $trueBoundaries, $params['boundary_tolerance']);
        $boundary['matchedTruth'] += matched_boundaries($trueBoundaries, $predictedBoundaries, $params['boundary_tolerance']);
        if ($decoder === 'POSTERIOR') foreach ($path as $t => $state) {
            $bin = min(9, (int) floor(10 * $result['confidence'][$t]));
            $bins[$bin]['positions']++;
            if ($state === $record['path'][$t]) $bins[$bin]['correct']++;
        }
    }
    $lines = array_merge([fields('EVALUATION', $model['name'], $decoder)], confusion_lines($matrix, $model['states']), metric_lines($matrix, $model['states']));
    $lines[] = fields('REGIONS', $model['states'][$params['segment_state']], 'predicted', $region['predicted'], 'true', $region['truth'],
        'precision', fraction($region['matchedPredicted'], $region['predicted']), 'recall', fraction($region['matchedTruth'], $region['truth']));
    $lines[] = fields('BOUNDARIES predicted', $boundary['predicted'], 'true', $boundary['truth'],
        'precision', fraction($boundary['matchedPredicted'], $boundary['predicted']), 'recall', fraction($boundary['matchedTruth'], $boundary['truth']));
    foreach ($bins as $b => $bin) {
        if ($bin['positions'] === 0) continue;
        $range = $b === 9 ? '0.9-1.0' : '0.' . $b . '-0.' . ($b + 1);
        $lines[] = fields('CALIBRATION', $range, 'positions', $bin['positions'], 'correct', $bin['correct'], 'accuracy', fraction($bin['correct'], $bin['positions']));
    }
    foreach ($recordLines as $line) $lines[] = $line;
    return compact('lines', 'correct');
}

function supervised_blocks($result, $data, $states, $params)
{
    $total = positions($data['train']);
    $selected = $result['selected'];
    $lines = ['CROSS_VALIDATION folds ' . $params['folds']];
    foreach ($result['candidates'] as $candidate) {
        $lines[] = fields('SMOOTHING', $candidate['smoothing']['text'], 'positions', $total, 'correct', $candidate['correct'], 'accuracy', fraction($candidate['correct'], $total));
    }
    $lines[] = 'SELECTED ' . $selected['smoothing']['text'];
    foreach ($selected['folds'] as $f => $fold) {
        $lines[] = fields('FOLD', $f + 1, 'records', $fold['records'], 'positions', $fold['positions'], 'correct', $fold['correct'], 'accuracy', fraction($fold['correct'], $fold['positions']));
    }
    $lines = array_merge($lines, confusion_lines($selected['matrix'], $states), metric_lines($selected['matrix'], $states));
    $learning = ['LEARNING_CURVE'];
    foreach ($result['learning'] as $r => $correct) $learning[] = fields('RECORDS', $r + 1, 'correct', $correct, 'accuracy', fraction($correct, positions($data['test'])));
    return [$lines, $learning];
}

function path_text($path, $names)
{
    $text = '';
    foreach ($path as $state) $text .= $names[$state];
    return $text;
}

function annotate($model, $records, $decoded, $params)
{
    $generator = new Minstd($params['posterior_seed']);
    $lines = [];
    $segmentLines = ['sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island'];
    foreach ($records as $i => $record) {
        $result = $decoded[$i];
        $samples = [];
        $segmentCount = 0;
        for ($sample = 0; $sample < $params['posterior_samples']; $sample++) {
            $path = posterior_path($model, $result['factors'], $generator);
            $samples[] = $path;
            $segmentCount += count(segments($path, $params));
        }
        $uncertain = 0;
        $confident = '';
        $imputed = '';
        foreach ($record['observations'] as $t => $symbol) {
            if ($result['confidence'][$t] < $params['confidence']) {
                $uncertain++;
                $confident .= '.';
            } else $confident .= $model['states'][$result['posterior'][$t]];
            if ($symbol >= 0) $imputed .= $model['symbols'][$symbol];
            else {
                $weights = [];
                foreach ($model['symbols'] as $c => $character) {
                    $weight = 0.0;
                    foreach ($model['states'] as $state => $name) $weight += $result['gamma'][$t][$state] * $model['emission'][$state][$c];
                    $weights[] = $weight;
                }
                $imputed .= strtolower($model['symbols'][argmax_index($weights)]);
            }
        }
        $differences = count($record['observations']) - correct_count($result['viterbi'], $result['posterior']);
        $lines[] = fields('SEQUENCE', $record['name'], 'length', count($record['observations']), 'loglik', real_number($result['loglik']),
            'viterbi', real_number($result['logprob']), 'differences', $differences, 'uncertain', $uncertain, 'expected_segments', real_number($segmentCount / $params['posterior_samples']));
        $lines[] = 'VITERBI ' . path_text($result['viterbi'], $model['states']);
        $lines[] = 'POSTERIOR ' . path_text($result['posterior'], $model['states']);
        $lines[] = 'CONFIDENT ' . $confident;
        $lines[] = 'IMPUTED ' . $imputed;
        foreach (['viterbi', 'posterior'] as $decoder) foreach (segments($result[$decoder], $params) as $segment) {
            $length = $segment['end'] - $segment['start'] + 1;
            $probability = 0.0;
            for ($t = $segment['start']; $t <= $segment['end']; $t++) $probability += $result['gamma'][$t][$params['segment_state']];
            $support = 0;
            foreach ($samples as $sample) {
                $count = 0;
                for ($t = $segment['start']; $t <= $segment['end']; $t++) if ($sample[$t] === $params['segment_state']) $count++;
                if (2 * $count > $length) $support++;
            }
            $judged = composition($record['observations'], $segment, $params);
            $segmentLines[] = implode(',', [$record['name'], $decoder, $segment['start'] + 1, $segment['end'] + 1, $length,
                real_number($probability / $length), $support, real_number($judged['rich']), real_number($judged['ratio']), $judged['island'] ? 'yes' : 'no']);
        }
    }
    return compact('lines', 'segmentLines');
}

function synthetic_report($model, $params)
{
    $generator = new Minstd($params['sample_seed']);
    $lines = [];
    $viterbiCorrect = 0;
    $posteriorCorrect = 0;
    for ($sample = 1; $sample <= $params['sample_count']; $sample++) {
        $generated = synthetic($model, $params['sample_length'], $generator);
        $result = decode($model, $generated['observations']);
        $vc = correct_count($generated['path'], $result['viterbi']);
        $pc = correct_count($generated['path'], $result['posterior']);
        $viterbiCorrect += $vc;
        $posteriorCorrect += $pc;
        $lines[] = fields('SAMPLE', $sample, 'loglik', real_number($result['loglik']), 'viterbi', real_number($result['logprob']), 'viterbi_correct', $vc, 'posterior_correct', $pc);
        $lines[] = 'STATES ' . path_text($generated['path'], $model['states']);
        $lines[] = 'SYMBOLS ' . path_text($generated['observations'], $model['symbols']);
        $lines[] = 'VITERBI ' . path_text($result['viterbi'], $model['states']);
        $lines[] = 'POSTERIOR ' . path_text($result['posterior'], $model['states']);
    }
    $total = $params['sample_count'] * $params['sample_length'];
    $lines[] = fields('TOTAL positions', $total, 'viterbi_accuracy', fraction($viterbiCorrect, $total), 'posterior_accuracy', fraction($posteriorCorrect, $total));
    return $lines;
}

function path_statistics($paths, $size)
{
    $counts = array_fill(0, $size, 0);
    $runCounts = array_fill(0, $size, 0);
    $total = 0;
    foreach ($paths as $path) {
        $total += count($path);
        foreach ($path as $state) $counts[$state]++;
        foreach (runs($path) as $run) $runCounts[$run['state']]++;
    }
    $occupancy = [];
    $meanRun = [];
    foreach ($counts as $i => $count) {
        $occupancy[] = $count / $total;
        $meanRun[] = $runCounts[$i] === 0 ? null : $count / $runCounts[$i];
    }
    return compact('occupancy', 'meanRun');
}

function stationary($model)
{
    $size = count($model['states']);
    $system = [];
    for ($j = 0; $j < $size - 1; $j++) {
        $row = [];
        for ($i = 0; $i < $size; $i++) $row[] = $model['transition'][$i][$j] - ($i === $j ? 1 : 0);
        $row[] = 0.0;
        $system[] = $row;
    }
    $system[] = array_fill(0, $size + 1, 1.0);
    for ($column = 0; $column < $size; $column++) {
        $pivot = $column;
        for ($row = $column + 1; $row < $size; $row++) if (abs($system[$row][$column]) > abs($system[$pivot][$column])) $pivot = $row;
        [$system[$column], $system[$pivot]] = [$system[$pivot], $system[$column]];
        $divisor = $system[$column][$column];
        for ($j = $column; $j <= $size; $j++) $system[$column][$j] /= $divisor;
        for ($row = 0; $row < $size; $row++) {
            if ($row === $column) continue;
            $factor = $system[$row][$column];
            for ($j = $column; $j <= $size; $j++) $system[$row][$j] -= $factor * $system[$column][$j];
        }
    }
    $result = [];
    foreach ($system as $row) $result[] = $row[$size];
    return $result;
}

function state_alignment($model, $records)
{
    $size = count($model['states']);
    $matrix = confusion($size);
    foreach ($records as $record) accumulate($matrix, $record['path'], viterbi($model, $record['observations'])['path']);
    $best = [];
    $agreement = -1;
    $visit = function ($permutation, $score) use (&$visit, &$best, &$agreement, $matrix, $size) {
        $column = count($permutation);
        if ($column === $size) {
            if ($score > $agreement) {
                $best = $permutation;
                $agreement = $score;
            }
            return;
        }
        for ($state = 0; $state < $size; $state++) {
            if (in_array($state, $permutation, true)) continue;
            $next = $permutation;
            $next[] = $state;
            $visit($next, $score + $matrix[$state][$column]);
        }
    };
    $visit([], 0);
    return ['permutation' => $best, 'agreement' => $agreement];
}

function input_report($data, $model)
{
    $labeled = array_merge($data['train'], $data['test']);
    $missing = 0;
    $labeledMissing = 0;
    foreach ($data['unlabeled'] as $record) $missing += $record['missing'];
    foreach ($labeled as $record) $labeledMissing += $record['missing'];
    $rejectedSequences = 0;
    foreach ($data['rejected'] as $rejection) if ($rejection['file'] === 'sequences.txt') $rejectedSequences++;
    $lines = ['INPUT', fields('SEQUENCES accepted', count($data['unlabeled']), 'rejected', $rejectedSequences, 'positions', positions($data['unlabeled']), 'missing', $missing),
        fields('LABELED train', count($data['train']), 'test', count($data['test']), 'rejected', count($data['rejected']) - $rejectedSequences,
            'positions', positions($labeled), 'missing', $labeledMissing)];
    foreach ($data['rejected'] as $rejected) $lines[] = fields('REJECT', $rejected['file'], 'line', $rejected['line'], $rejected['name'], $rejected['reason']);
    $symbols = array_fill(0, count($model['symbols']), 0);
    foreach ($data['unlabeled'] as $record) foreach ($record['observations'] as $symbol) if ($symbol >= 0) $symbols[$symbol]++;
    $observed = positions($data['unlabeled']) - $missing;
    $composition = ['COMPOSITION'];
    foreach ($model['symbols'] as $i => $symbol) {
        $composition[] = $symbol;
        $composition[] = real_number($symbols[$i] / $observed);
    }
    $lines[] = fields(...$composition);
    foreach (['TRAIN', 'TEST'] as $role) {
        $summary = path_statistics(array_column($data[strtolower($role)], 'path'), count($model['states']));
        foreach ($model['states'] as $state => $name) {
            $lines[] = fields('TRUTH', $role, $name, 'occupancy', real_number($summary['occupancy'][$state]), 'mean_run', real_number($summary['meanRun'][$state]));
        }
    }
    return $lines;
}

function training_report($bw, $vt, $supervised, $data, $decoded, $scores, $params)
{
    $lines = [fields('TRAINING BAUM_WELCH iterations', $params['iterations'], 'initial_loglik', real_number($bw['history'][0]['loglik']),
        'final_loglik', real_number($bw['history'][count($bw['history']) - 1]['loglik']), 'violations', $bw['violations'], 'best_heldout_iteration', $bw['best']),
        fields('TRAINING VITERBI_TRAINING iterations', $vt['iterations'], 'converged', $vt['converged'] ? 'yes' : 'no'),
        'TRAINING SUPERVISED smoothing ' . $supervised['selected']['smoothing']['text']];
    $preference = array_fill(0, count(MODEL_NAMES), 0);
    foreach ($data['unlabeled'] as $i => $record) {
        $loglik = [];
        foreach ($decoded as $results) $loglik[] = $results[$i]['loglik'];
        $preference[argmax_index($loglik)]++;
    }
    $line = ['PREFERENCE'];
    foreach (MODEL_NAMES as $i => $name) { $line[] = $name; $line[] = $preference[$i]; }
    $lines[] = fields(...$line);
    for ($left = 0; $left < count(MODEL_NAMES); $left++) for ($right = $left + 1; $right < count(MODEL_NAMES); $right++) {
        $agreement = 0;
        foreach ($data['unlabeled'] as $i => $record) $agreement += correct_count($decoded[$left][$i]['viterbi'], $decoded[$right][$i]['viterbi']);
        $lines[] = fields('AGREEMENT', MODEL_NAMES[$left], MODEL_NAMES[$right], fraction($agreement, positions($data['unlabeled'])));
    }
    foreach (DECODERS as $decoder => $name) {
        $values = [];
        foreach ($scores as $row) $values[] = $row[$decoder];
        $best = argmax_index($values);
        $lines[] = fields('BEST', $name, MODEL_NAMES[$best], 'accuracy', fraction($scores[$best][$decoder], positions($data['test'])));
    }
    return $lines;
}

function model_report($model, $data, $decoded, $testDecoded, $params)
{
    $loglik = 0.0;
    $testLoglik = 0.0;
    $observed = 0;
    $segmentCount = 0;
    $segmentLength = 0;
    $islands = 0;
    foreach ($data['unlabeled'] as $i => $record) {
        $loglik += $decoded[$i]['loglik'];
        $observed += count($record['observations']) - $record['missing'];
        foreach (segments($decoded[$i]['viterbi'], $params) as $segment) {
            $segmentCount++;
            $segmentLength += $segment['end'] - $segment['start'] + 1;
            if (composition($record['observations'], $segment, $params)['island']) $islands++;
        }
    }
    foreach ($testDecoded as $result) $testLoglik += $result['loglik'];
    $distribution = stationary($model);
    $summary = path_statistics(array_column($decoded, 'viterbi'), count($model['states']));
    $alignment = state_alignment($model, $data['train']);
    $lines = ['MODEL ' . $model['name'], fields('LOGLIK unlabeled', real_number($loglik), 'per_symbol', real_number($loglik / $observed), 'test', real_number($testLoglik)),
        fields('SEGMENTS count', $segmentCount, 'mean_length', real_number($segmentCount === 0 ? null : $segmentLength / $segmentCount), 'islands', $islands)];
    $mapping = [];
    foreach ($model['states'] as $i => $state) $mapping[] = $state . '=' . $model['states'][$alignment['permutation'][$i]];
    $lines[] = fields('ALIGNMENT', implode(' ', $mapping), 'agreement', fraction($alignment['agreement'], positions($data['train'])));
    foreach ($model['states'] as $state => $name) {
        $lines[] = fields('STATE', $name, 'stationary', real_number($distribution[$state]), 'duration', real_number(1 / (1 - $model['transition'][$state][$state])),
            'occupancy', real_number($summary['occupancy'][$state]), 'mean_run', real_number($summary['meanRun'][$state]));
    }
    return $lines;
}

function join_blocks($blocks)
{
    $lines = [];
    foreach ($blocks as $block) {
        if (count($lines) > 0) $lines[] = '';
        foreach ($block as $line) $lines[] = $line;
    }
    return $lines;
}

function main()
{
    $input = read_inputs();
    $params = parameters($input['parameters'], $input['model']);
    $data = validate_input($input, $params);
    $bw = baum_welch($input['model'], $data, $params);
    $vt = viterbi_training($input['model'], $data['unlabeled'], $params);
    $supervised = supervised_training($input['model'], $data, $params);
    $models = [$input['model'], $bw['model'], $vt['model'], $supervised['model']];
    $decoded = [];
    $testDecoded = [];
    foreach ($models as $model) {
        $unlabeledResults = [];
        $testResults = [];
        foreach ($data['unlabeled'] as $record) $unlabeledResults[] = decode($model, $record['observations']);
        foreach ($data['test'] as $record) $testResults[] = decode($model, $record['observations']);
        $decoded[] = $unlabeledResults;
        $testDecoded[] = $testResults;
    }
    $evaluation = [];
    $scores = [];
    foreach ($models as $i => $model) {
        $row = [];
        foreach (DECODERS as $decoder) {
            $result = evaluation_block($model, $data['test'], $testDecoded[$i], $decoder, $params);
            $evaluation[] = $result['lines'];
            $row[] = $result['correct'];
        }
        $scores[] = $row;
    }
    foreach (supervised_blocks($supervised, $data, $input['model']['states'], $params) as $block) $evaluation[] = $block;
    $annotation = annotate($bw['model'], $data['unlabeled'], $decoded[1], $params);
    $report = [input_report($data, $input['model']), training_report($bw, $vt, $supervised, $data, $decoded, $scores, $params)];
    foreach ($models as $i => $model) $report[] = model_report($model, $data, $decoded[$i], $testDecoded[$i], $params);
    $trained = [];
    foreach (array_slice($models, 1) as $model) $trained[] = model_lines($model);
    write_lines('trained_model.txt', join_blocks($trained));
    write_lines('loglik_trace.csv', $bw['lines']);
    write_lines('viterbi_trace.csv', $vt['lines']);
    write_lines('decodings.txt', $annotation['lines']);
    write_lines('segments.csv', $annotation['segmentLines']);
    write_lines('samples.txt', synthetic_report($bw['model'], $params));
    write_lines('evaluation.txt', join_blocks($evaluation));
    write_lines('report.txt', join_blocks($report));
}

main();
