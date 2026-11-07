<?php

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/kernels.php';
require_once __DIR__ . '/smo.php';
require_once __DIR__ . '/multiclass.php';
require_once __DIR__ . '/evaluation.php';

function fields(...$values) { return implode(' ', $values); }

function support($model)
{
    $total = 0; $bound = 0; $free = 0;
    foreach ($model->alpha as $a) if ($a > 0) {
        $total++;
        if ($a == $model->C) $bound++; else $free++;
    }
    return compact('total', 'bound', 'free');
}

function support_text($sv)
{
    return fields('support_vectors', $sv['total'], 'bound', $sv['bound'], 'free', $sv['free']);
}

function run_info($model)
{
    if (is_array($model)) return fields('passes', $model['passes'], 'steps', $model['steps'], 'converged', $model['converged'] ? 'yes' : 'no');
    return fields('passes', $model->full + $model->nonbound, 'steps', $model->steps, 'converged', $model->converged ? 'yes' : 'no');
}

function objective($model, $alpha = null)
{
    $alpha = $alpha ?? $model->alpha;
    $sums = training_sums($model, $alpha);
    $q = 0.0; $total = 0.0;
    foreach ($alpha as $i => $value) {
        $q += $value * $model->labels[$i] * $sums[$i];
        $total += $value;
    }
    return ['sums' => $sums, 'q' => $q, 'dual' => $total - $q / 2];
}

function measure($model, $test)
{
    $result = objective($model);
    $values = [];
    foreach ($result['sums'] as $sum) $values[] = $sum - $model->b;
    $testValues = [];
    foreach ($test as $row) $testValues[] = decision($model, $row['point']);
    return ['model' => $model, 'q' => $result['q'], 'dual' => $result['dual'], 'values' => $values, 'testValues' => $testValues,
        'sv' => support($model), 'trainCorrect' => binary($model->labels, $values)['correct'], 'testStats' => binary(array_column($test, 'label'), $testValues)];
}

function cross_validate($train, $params, $matrices)
{
    $partition = folds(count($train), $params['folds']);
    $combinations = []; $best = [];
    foreach ($params['kernels'] as $kernel) {
        $winner = null;
        foreach ($params['cs'] as $C) {
            $result = ['kernel' => $kernel, 'C' => $C, 'correct' => 0, 'support' => 0, 'passes' => 0, 'steps' => 0,
                'values' => array_fill(0, count($train), 0.0), 'folds' => []];
            foreach ($partition as $fold) {
                $points = []; $labels = [];
                foreach ($fold['train'] as $i) { $points[] = $train[$i]['point']; $labels[] = $train[$i]['label']; }
                $model = smo_train($points, $labels, matrix_subset($matrices[$kernel['index']], $fold['train']), $C, $kernel, $params);
                $correct = 0;
                foreach ($fold['test'] as $i) {
                    $result['values'][$i] = decision($model, $train[$i]['point']);
                    if (sign_value($result['values'][$i]) === $train[$i]['label']) $correct++;
                }
                $sv = support($model); $passes = $model->full + $model->nonbound;
                $result['folds'][] = ['train' => count($fold['train']), 'test' => count($fold['test']), 'correct' => $correct,
                    'support' => $sv['total'], 'passes' => $passes, 'steps' => $model->steps, 'converged' => $model->converged];
                $result['correct'] += $correct; $result['support'] += $sv['total'];
                $result['passes'] += $passes; $result['steps'] += $model->steps;
            }
            $combinations[] = $result;
            if ($winner === null || $result['correct'] > $winner['correct']) $winner = $result;
        }
        $best[] = $winner;
    }
    $ranking = $combinations;
    usort($ranking, fn($a, $b) => ($b['correct'] <=> $a['correct']) ?: (($a['C'] <=> $b['C']) ?: ($a['kernel']['index'] <=> $b['kernel']['index'])));
    return ['combinations' => $combinations, 'best' => $best, 'ranking' => $ranking, 'selected' => $ranking[0]];
}

function cross_validation_lines($cv, $n, $params)
{
    $lines = [fields('cross_validation folds', $params['folds'], 'examples', $n)];
    foreach ($cv['best'] as $best) $lines[] = fields('best', $best['kernel']['name'], 'C', fixed($best['C'], 4), 'correct', $best['correct'] . '/' . $n, 'accuracy', ratio($best['correct'], $n));
    $lines[] = fields('selected', $cv['selected']['kernel']['name'], 'C', fixed($cv['selected']['C'], 4));
    $lines[] = 'ranking';
    foreach ($cv['ranking'] as $i => $entry) $lines[] = fields($i + 1, $entry['kernel']['name'], 'C', fixed($entry['C'], 4), 'correct', $entry['correct'] . '/' . $n);
    $lines[] = fields('cv_detail', $cv['selected']['kernel']['name'], 'C', fixed($cv['selected']['C'], 4));
    foreach ($cv['selected']['folds'] as $i => $fold) $lines[] = fields('fold', $i + 1, 'train', $fold['train'], 'test', $fold['test'],
        'correct', $fold['correct'], 'support_vectors', $fold['support'], run_info($fold));
    return $lines;
}

function final_model_lines(&$result, $train, $test, $params)
{
    $model = $result['model']; $q = $result['q']; $dual = $result['dual']; $values = $result['values'];
    $testValues = $result['testValues']; $sv = $result['sv']; $testStats = $result['testStats'];
    $n = count($train); $m = count($test);
    $sy = 0.0; $sg = 0.0; $maximum = null; $minimum = null;
    for ($i = 0; $i < $n; $i++) {
        if ($maximum === null || $model->Q[$i][$i] > $maximum) $maximum = $model->Q[$i][$i];
        for ($j = 0; $j < $n; $j++) {
            $sy += $model->labels[$i] * $model->labels[$j] * $model->Q[$i][$j];
            $sg += $model->Q[$i][$j] * $model->Q[$i][$j];
            if ($minimum === null || $model->Q[$i][$j] < $minimum) $minimum = $model->Q[$i][$j];
        }
    }
    $radius = $maximum - $minimum; $norm = sqrt($q);
    $equality = 0.0; $w1 = 0.0; $w2 = 0.0; $xi = 0.0; $violations = 0; $maxViolation = 0.0; $estimatedErrors = 0;
    $byClass = ['positive' => ['bound' => 0, 'free' => 0], 'negative' => ['bound' => 0, 'free' => 0]];
    for ($i = 0; $i < $n; $i++) {
        $a = $model->alpha[$i]; $y = $model->labels[$i];
        $equality += $a * $y;
        $w1 += $a * $y * $train[$i]['point'][0]; $w2 += $a * $y * $train[$i]['point'][1];
        $hinge = max(0.0, 1 - $y * $values[$i]); $r = $y * $values[$i] - 1;
        $xi += $hinge;
        $violation = $a == 0 ? max(0.0, -$r) : ($a == $model->C ? max(0.0, $r) : abs($r));
        if ($violation > $params['tau']) $violations++;
        $maxViolation = max($maxViolation, $violation);
        if (2 * $a * $radius + $hinge >= 1) $estimatedErrors++;
        if ($a > 0) $byClass[$y === 1 ? 'positive' : 'negative'][$a == $model->C ? 'bound' : 'free']++;
    }
    $result['weights'] = [$w1, $w2];
    $primal = $q / 2 + $model->C * $xi;
    $inside = 0; $positiveSum = 0.0; $negativeSum = 0.0; $positives = 0; $negatives = 0;
    foreach ($test as $i => $row) {
        if (abs($testValues[$i]) < 1) $inside++;
        if ($row['label'] === 1) { $positiveSum += $testValues[$i]; $positives++; }
        else { $negativeSum += $testValues[$i]; $negatives++; }
    }
    $lines = [fields('model', $model->kernel['name']), 'kernel ' . kernel_description($model->kernel), 'C ' . fixed($model->C, 4),
        'alignment ' . fixed($sy / ($n * sqrt($sg)), 6), fields('passes', $model->full + $model->nonbound, 'full', $model->full, 'nonbound', $model->nonbound, 'converged', $model->converged ? 'yes' : 'no'),
        fields('examined', $model->examined, 'steps', $model->steps), fields('choice heuristic', $model->choice['heuristic'], 'nonbound_loop', $model->choice['nonbound_loop'], 'full_loop', $model->choice['full_loop']),
        fields('clipping none', $model->clipping['none'], 'lower', $model->clipping['lower'], 'upper', $model->clipping['upper']), support_text($sv),
        'b ' . fixed($model->b, 6), 'equality ' . fixed($equality, 6)];
    if ($model->kernel['kind'] === 'linear') $lines[] = fields('w', fixed($w1, 6), fixed($w2, 6));
    $positive = $byClass['positive']; $negative = $byClass['negative'];
    $tp = $testStats['tp']; $fp = $testStats['fp']; $tn = $testStats['tn']; $fn = $testStats['fn']; $correct = $testStats['correct'];
    $lines[] = fields('sv_by_class positive bound', $positive['bound'], 'free', $positive['free'], 'negative bound', $negative['bound'], 'free', $negative['free']);
    $lines[] = fields('norm', fixed($norm, 6), 'margin', fixed(2 / $norm, 6));
    $lines[] = 'dual_objective ' . fixed($dual, 6);
    $lines[] = 'primal_objective ' . fixed($primal, 6);
    $lines[] = 'duality_gap ' . fixed($primal - $dual, 6);
    $lines[] = fields('kkt_violations', $violations, 'max', fixed($maxViolation, 6));
    $lines[] = fields('xi_alpha radius', fixed($radius, 6), 'errors', $estimatedErrors . '/' . $n, 'accuracy', ratio($n - $estimatedErrors, $n));
    $lines[] = fields('train correct', $result['trainCorrect'] . '/' . $n, 'accuracy', ratio($result['trainCorrect'], $n));
    $lines[] = fields('test correct', $correct . '/' . $m, 'accuracy', ratio($correct, $m), 'tp', $tp, 'fp', $fp, 'tn', $tn, 'fn', $fn);
    $lines[] = fields('test precision', ratio($tp, $tp + $fp), 'recall', ratio($tp, $tp + $fn), 'f1', ratio(2 * $tp, 2 * $tp + $fp + $fn),
        'auc', fixed(auc(array_column($test, 'label'), $testValues), 4));
    $lines[] = 'test inside_margin ' . $inside;
    $lines[] = fields('test mean_decision positive', fixed($positiveSum / $positives, 4), 'negative', fixed($negativeSum / $negatives, 4));
    foreach ($model->alpha as $i => $alpha) if ($alpha > 0) $lines[] = fields('sv', $train[$i]['id'], 'y', $model->labels[$i], 'alpha', fixed($alpha, 6), 'f', fixed($values[$i], 4), $alpha == $model->C ? 'bound' : 'free');
    return $lines;
}

function training_log($model)
{
    $lines = ['training_log ' . $model->kernel['name']];
    for ($i = 0; $i < count($model->records);) {
        $first = $model->records[$i];
        if ($first['kind'] === 'full') {
            $lines[] = fields('pass', $first['number'], 'full examined', $first['examined'], 'changed', $first['changed'],
                'dual_objective', fixed(objective($model, $first['alpha'])['dual'], 6));
            $i++;
        } else {
            $examined = 0; $changed = 0; $last = $first['number'];
            while ($i < count($model->records) && $model->records[$i]['kind'] === 'nonbound') {
                $record = $model->records[$i++];
                $examined += $record['examined']; $changed += $record['changed']; $last = $record['number'];
            }
            $lines[] = fields('passes', $first['number'] . '-' . $last, 'nonbound examined', $examined, 'changed', $changed);
        }
    }
    return $lines;
}

function selected_analyses($selected, $train, $test, $params)
{
    $model = $selected['model']; $n = count($train); $m = count($test);
    $path = ['c_path ' . $model->kernel['name']];
    foreach ($params['cs'] as $C) {
        $fitted = smo_train($model->points, $model->labels, $model->Q, $C, $model->kernel, $params);
        $result = measure($fitted, $test);
        $path[] = fields('C', fixed($C, 4), support_text($result['sv']), 'dual_objective', fixed($result['dual'], 6),
            'train', $result['trainCorrect'] . '/' . $n, 'test', $result['testStats']['correct'] . '/' . $m, run_info($fitted));
    }
    $learning = [fields('learning_curve', $model->kernel['name'], 'C', fixed($model->C, 4))];
    foreach ($params['learningCurve'] as $percentage) {
        $size = intdiv($n * $percentage, 100);
        $indices = range(0, $size - 1);
        $fitted = smo_train(array_slice($model->points, 0, $size), array_slice($model->labels, 0, $size), matrix_subset($model->Q, $indices), $model->C, $model->kernel, $params);
        $result = measure($fitted, $test);
        $learning[] = fields('size', $size, 'support_vectors', $result['sv']['total'], 'train', $result['trainCorrect'] . '/' . $size,
            'test', $result['testStats']['correct'] . '/' . $m, run_info($fitted));
    }
    return [training_log($model), $path, $learning];
}

function probability($value, $A, $B) { return 1 / (1 + exp($A * $value + $B)); }

function calibration_nll($values, $targets, $A, $B)
{
    $sum = 0.0;
    foreach ($values as $i => $value) {
        $p = probability($value, $A, $B); $target = $targets[$i];
        $sum += $target * log($p) + (1 - $target) * log(1 - $p);
    }
    return -$sum;
}

function calibrate($selectedCV, $selected, $train, $test, $params)
{
    $values = $selectedCV['values']; $n = count($train); $m = count($test);
    $positives = 0;
    foreach ($train as $row) if ($row['label'] === 1) $positives++;
    $negatives = $n - $positives;
    $targets = [];
    foreach ($train as $row) $targets[] = $row['label'] === 1 ? ($positives + 1) / ($positives + 2) : 1 / ($negatives + 2);
    $A = 0.0; $B = log(($negatives + 1) / ($positives + 1));
    $lines = [fields('calibration', $selected['model']->kernel['name'], 'C', fixed($selected['model']->C, 4), 'positives', $positives, 'negatives', $negatives),
        fields('start A', fixed($A, 6), 'B', fixed($B, 6), 'nll', fixed(calibration_nll($values, $targets, $A, $B), 6))];
    for ($iteration = 1; $iteration <= $params['newtonIterations']; $iteration++) {
        $g1 = 0.0; $g2 = 0.0; $h11 = 0.0; $h21 = 0.0; $h22 = 0.0;
        foreach ($values as $i => $v) {
            $p = probability($v, $A, $B); $target = $targets[$i];
            $g1 += $v * ($target - $p); $g2 += $target - $p;
            $h11 += $v * $v * $p * (1 - $p); $h21 += $v * $p * (1 - $p); $h22 += $p * (1 - $p);
        }
        $det = $h11 * $h22 - $h21 * $h21;
        $nextA = $A - ($h22 * $g1 - $h21 * $g2) / $det;
        $nextB = $B - ($h11 * $g2 - $h21 * $g1) / $det;
        $A = $nextA; $B = $nextB;
        $lines[] = fields('iteration', $iteration, 'A', fixed($A, 6), 'B', fixed($B, 6), 'nll', fixed(calibration_nll($values, $targets, $A, $B), 6));
    }
    $probabilities = [];
    foreach ($selected['testValues'] as $value) $probabilities[] = probability($value, $A, $B);
    $bins = array_fill(0, 5, ['count' => 0, 'sum' => 0.0, 'positive' => 0]);
    $logSum = 0.0; $brierSum = 0.0;
    foreach ($test as $i => $row) {
        $p = $probabilities[$i]; $positive = $row['label'] === 1;
        $logSum += log($positive ? $p : 1 - $p);
        $error = $p - ($positive ? 1 : 0); $brierSum += $error * $error;
        $bin = min(4, (int) floor($p * 5));
        $bins[$bin]['count']++; $bins[$bin]['sum'] += $p;
        if ($positive) $bins[$bin]['positive']++;
    }
    $lines[] = fields('test log_loss', fixed(-$logSum / $m, 6), 'brier', fixed($brierSum / $m, 6));
    $ranges = ['0.0-0.2', '0.2-0.4', '0.4-0.6', '0.6-0.8', '0.8-1.0'];
    foreach ($bins as $i => $bin) $lines[] = fields('bin', $ranges[$i], 'count', $bin['count'], 'mean_probability',
        $bin['count'] ? fixed($bin['sum'] / $bin['count'], 4) : '-', 'positive_rate', ratio($bin['positive'], $bin['count']));
    $closest = range(0, $m - 1);
    usort($closest, fn($a, $b) => (abs($selected['testValues'][$a]) <=> abs($selected['testValues'][$b])) ?: ($a <=> $b));
    foreach (array_slice($closest, 0, 5) as $i) $lines[] = fields('closest', $test[$i]['id'], 'label', $test[$i]['label'],
        'decision', fixed($selected['testValues'][$i], 4), 'probability', fixed($probabilities[$i], 4));
    return compact('A', 'B', 'probabilities', 'lines');
}

function linear_value($weights, $point) { return $weights[0] * $point[0] + $weights[1] * $point[1] + $weights[2]; }

function pegasos($train, $test, $comparison, $params)
{
    $lambda = $params['pegasos']['lambda']; $iterations = $params['pegasos']['iterations']; $seed = $params['pegasos']['seed'];
    $n = count($train); $m = count($test);
    $rho = $seed; $w1 = 0.0; $w2 = 0.0; $w0 = 0.0; $s1 = 0.0; $s2 = 0.0; $s0 = 0.0; $updates = 0;
    $lines = [fields('pegasos lambda', fixed($lambda, 4), 'iterations', $iterations, 'seed', $seed)];
    for ($t = 1; $t <= $iterations; $t++) {
        $rho = (48271 * $rho) % 2147483647;
        $row = $train[$rho % $n]; $eta = 1 / ($lambda * $t); $sigma = 1 - $eta * $lambda;
        $oldValue = $w1 * $row['point'][0] + $w2 * $row['point'][1] + $w0;
        if ($row['label'] * $oldValue < 1) {
            $w1 = $sigma * $w1 + $eta * $row['label'] * $row['point'][0];
            $w2 = $sigma * $w2 + $eta * $row['label'] * $row['point'][1];
            $w0 = $sigma * $w0 + $eta * $row['label'];
            $updates++;
        } else { $w1 = $sigma * $w1; $w2 = $sigma * $w2; $w0 = $sigma * $w0; }
        $s1 += $w1; $s2 += $w2; $s0 += $w0;
        if ($t % intdiv($iterations, 10) === 0) {
            $xi = 0.0; $correct = 0;
            foreach ($train as $example) {
                $value = $w1 * $example['point'][0] + $w2 * $example['point'][1] + $w0;
                $xi += max(0.0, 1 - $example['label'] * $value);
                if (sign_value($value) === $example['label']) $correct++;
            }
            $objective = $lambda / 2 * ($w1 * $w1 + $w2 * $w2 + $w0 * $w0) + $xi / $n;
            $lines[] = fields('checkpoint', $t, 'objective', fixed($objective, 6), 'train', $correct . '/' . $n);
        }
    }
    $weights = [$w1, $w2, $w0]; $average = [$s1 / $iterations, $s2 / $iterations, $s0 / $iterations];
    $values = []; $trainValues = []; $averageValues = [];
    foreach ($test as $row) { $values[] = linear_value($weights, $row['point']); $averageValues[] = linear_value($average, $row['point']); }
    foreach ($train as $row) $trainValues[] = linear_value($weights, $row['point']);
    $trainCorrect = binary(array_column($train, 'label'), $trainValues)['correct'];
    $testCorrect = binary(array_column($test, 'label'), $values)['correct'];
    $averageCorrect = binary(array_column($test, 'label'), $averageValues)['correct'];
    [$v1, $v2] = $comparison['weights'];
    $cosine = ($w1 * $v1 + $w2 * $v2) / (sqrt($w1 * $w1 + $w2 * $w2) * sqrt($v1 * $v1 + $v2 * $v2));
    $agreement = 0;
    foreach ($test as $i => $row) if (sign_value($values[$i]) === sign_value($comparison['testValues'][$i])) $agreement++;
    $lines[] = 'updates ' . $updates;
    $lines[] = fields('w', fixed($w1, 6), fixed($w2, 6), 'bias', fixed($w0, 6));
    $lines[] = fields('train correct', $trainCorrect . '/' . $n, 'accuracy', ratio($trainCorrect, $n));
    $lines[] = fields('test correct', $testCorrect . '/' . $m, 'accuracy', ratio($testCorrect, $m));
    $lines[] = fields('average w', fixed($average[0], 6), fixed($average[1], 6), 'bias', fixed($average[2], 6), 'test correct', $averageCorrect . '/' . $m);
    $lines[] = fields('compare', $comparison['model']->kernel['name'], 'cosine', fixed($cosine, 6), 'test_agreement', $agreement . '/' . $m);
    return compact('weights', 'values', 'lines');
}

function mcnemar($finals, $peg, $test)
{
    $comparisons = [];
    foreach ($finals as $result) $comparisons[] = ['name' => $result['model']->kernel['name'], 'values' => $result['testValues']];
    $comparisons[] = ['name' => 'pegasos', 'values' => $peg['values']];
    $lines = ['mcnemar'];
    for ($a = 0; $a < count($comparisons); $a++) for ($b = $a + 1; $b < count($comparisons); $b++) {
        $first = 0; $second = 0;
        foreach ($test as $i => $row) {
            $correctA = sign_value($comparisons[$a]['values'][$i]) === $row['label'];
            $correctB = sign_value($comparisons[$b]['values'][$i]) === $row['label'];
            if ($correctA && !$correctB) $first++;
            if ($correctB && !$correctA) $second++;
        }
        $difference = abs($first - $second) - 1;
        $chi = $first + $second > 0 ? fixed($difference * $difference / ($first + $second), 4) : '-';
        $lines[] = fields($comparisons[$a]['name'], $comparisons[$b]['name'], 'only_first', $first, 'only_second', $second, 'chi2', $chi);
    }
    return $lines;
}

function multiclass_lines($models, $train, $test, $kernel, $params)
{
    $trainResults = []; $testResults = [];
    foreach ($train as $row) $trainResults[] = multiclass_classify($models, $row['point']);
    foreach ($test as $row) $testResults[] = multiclass_classify($models, $row['point']);
    $lines = [fields('multiclass kernel', $kernel['name'], 'C', fixed($params['multiC'], 4), 'classes 3 train', count($train), 'test', count($test)), 'ovr'];
    foreach ($models['ovr'] as $i => $model) {
        $positives = 0; $correct = 0;
        foreach ($model->labels as $label) if ($label === 1) $positives++;
        foreach ($test as $j => $row) if (sign_value($testResults[$j]['g'][$i]) === ($row['class'] === $i + 1 ? 1 : -1)) $correct++;
        $lines[] = fields('model', ($i + 1) . '-rest', 'examples', count($train), 'positives', $positives, support_text(support($model)),
            'b', fixed($model->b, 6), run_info($model), 'test', $correct . '/' . count($test));
    }
    $lines[] = 'ovo';
    foreach ($models['ovo'] as $i => $model) {
        [$a, $b] = PAIRS[$i]; $positives = 0; $correct = 0; $count = 0;
        foreach ($model->labels as $label) if ($label === 1) $positives++;
        foreach ($test as $j => $row) if ($row['class'] === $a || $row['class'] === $b) {
            $count++;
            if (sign_value($testResults[$j]['h'][$i]) === ($row['class'] === $a ? 1 : -1)) $correct++;
        }
        $lines[] = fields('model', $a . '-' . $b, 'examples', count($model->points), 'positives', $positives, support_text(support($model)),
            'b', fixed($model->b, 6), run_info($model), 'test', $correct . '/' . $count);
    }
    $lines[] = 'predictions';
    foreach ($testResults as $i => $result) {
        $g = []; $h = [];
        foreach ($result['g'] as $value) $g[] = fixed($value, 4);
        foreach ($result['h'] as $value) $h[] = fixed($value, 4);
        $lines[] = fields($test[$i]['id'], 'class', $test[$i]['class'], 'ovr', implode(' ', $g), 'pred', $result['ovr'],
            'ovo', implode(' ', $h), 'votes', implode(' ', $result['votes']), 'pred', $result['ovo']);
    }
    foreach ([['train', $train, $trainResults], ['test', $test, $testResults]] as [$name, $rows, $results]) {
        $ovr = 0; $ovo = 0; $agreement = 0; $ties = 0;
        foreach ($rows as $i => $row) {
            if ($results[$i]['ovr'] === $row['class']) $ovr++;
            if ($results[$i]['ovo'] === $row['class']) $ovo++;
            if ($results[$i]['ovr'] === $results[$i]['ovo']) $agreement++;
            if ($results[$i]['voteTie']) $ties++;
        }
        $lines[] = fields($name, 'ovr', $ovr . '/' . count($rows), ratio($ovr, count($rows)), 'ovo', $ovo . '/' . count($rows), ratio($ovo, count($rows)),
            'agreement', $agreement . '/' . count($rows), 'vote_ties', $ties);
    }
    foreach (['ovr', 'ovo'] as $kind) {
        $predictions = [];
        foreach ($testResults as $result) $predictions[] = $result[$kind];
        $U = confusion(array_column($test, 'class'), $predictions);
        $lines[] = 'confusion ' . $kind;
        foreach ($U as $row) $lines[] = implode(' ', $row);
        for ($k = 0; $k < 3; $k++) {
            $column = 0; $row = 0;
            for ($j = 0; $j < 3; $j++) { $column += $U[$j][$k]; $row += $U[$k][$j]; }
            $lines[] = fields('class', $k + 1, 'precision', ratio($U[$k][$k], $column), 'recall', ratio($U[$k][$k], $row));
        }
    }
    return $lines;
}

function frame_grid($grid, $width)
{
    $border = '+' . str_repeat('-', $width) . '+';
    $lines = [$border];
    foreach ($grid as $row) $lines[] = '|' . implode('', $row) . '|';
    $lines[] = $border;
    return $lines;
}

function grid_count($grid, $character)
{
    $total = 0;
    foreach ($grid as $row) foreach ($row as $cell) if ($cell === $character) $total++;
    return $total;
}

function overlay(&$grid, $rows, $params, $dx, $dy, $prefer, $character)
{
    $W = $params['width']; $H = $params['height'];
    $owners = array_fill(0, $W * $H, -1);
    $outside = 0; $points = 0;
    foreach ($rows as $i => $row) {
        $c = (int) floor(($row['point'][0] - $params['xMin']) / $dx);
        $r = (int) floor(($params['yMax'] - $row['point'][1]) / $dy);
        if ($c < 0 || $c >= $W || $r < 0 || $r >= $H) { $outside++; continue; }
        $cell = $r * $W + $c;
        if ($owners[$cell] < 0) { $owners[$cell] = $i; $points++; }
        elseif ($prefer($i, $owners[$cell])) $owners[$cell] = $i;
    }
    for ($r = 0; $r < $H; $r++) for ($c = 0; $c < $W; $c++) {
        if ($owners[$r * $W + $c] >= 0) $grid[$r][$c] = $character($owners[$r * $W + $c]);
    }
    return compact('outside', 'points');
}

function decision_plots($finals, $selected, $calibration, $multiModels, $multiKernel, $train, $multiTrain, $params)
{
    $W = $params['width']; $H = $params['height'];
    $dx = ($params['xMax'] - $params['xMin']) / $W; $dy = ($params['yMax'] - $params['yMin']) / $H;
    $binaryGrid = []; $probabilityGrid = []; $multiGrid = []; $signs = array_fill(0, count($finals), []);
    $levels = array_fill(0, 10, 0);
    for ($r = 0; $r < $H; $r++) {
        $binaryGrid[] = []; $probabilityGrid[] = []; $multiGrid[] = [];
        for ($c = 0; $c < $W; $c++) {
            $point = [$params['xMin'] + ($c + 0.5) * $dx, $params['yMax'] - ($r + 0.5) * $dy];
            $values = [];
            foreach ($finals as $result) $values[] = decision($result['model'], $point);
            $value = $values[$selected['model']->kernel['index']];
            $binaryGrid[$r][] = $value >= 1 ? '+' : ($value > 0 ? '.' : ($value > -1 ? '-' : ' '));
            $digit = min(9, (int) floor(probability($value, $calibration['A'], $calibration['B']) * 10));
            $probabilityGrid[$r][] = (string) $digit; $levels[$digit]++;
            foreach ($values as $i => $v) $signs[$i][] = sign_value($v);
            $result = multiclass_classify($multiModels, $point);
            $multiGrid[$r][] = $result['ovr'] !== $result['ovo'] ? '?' : [' ', '.', ':'][$result['ovr'] - 1];
        }
    }
    $binaryOverlay = overlay($binaryGrid, $train, $params, $dx, $dy,
        fn($i, $old) => $selected['model']->alpha[$i] > 0 && !($selected['model']->alpha[$old] > 0),
        fn($i) => $train[$i]['label'] === 1 ? ($selected['model']->alpha[$i] > 0 ? 'X' : 'x') : ($selected['model']->alpha[$i] > 0 ? 'O' : 'o'));
    $multiOverlay = overlay($multiGrid, $multiTrain, $params, $dx, $dy, fn($i, $old) => false, fn($i) => (string) $multiTrain[$i]['class']);
    $lines = [fields('binary', $selected['model']->kernel['name'], 'C', fixed($selected['model']->C, 4)),
        fields('x', fixed($params['xMin'], 4), fixed($params['xMax'], 4), 'y', fixed($params['yMin'], 4), fixed($params['yMax'], 4), 'grid', $W . 'x' . $H)];
    foreach (frame_grid($binaryGrid, $W) as $line) $lines[] = $line;
    $lines[] = fields('cells outer_positive', grid_count($binaryGrid, '+'), 'inner_positive', grid_count($binaryGrid, '.'), 'inner_negative', grid_count($binaryGrid, '-'),
        'outer_negative', grid_count($binaryGrid, ' '), 'points', $binaryOverlay['points'], 'outside', $binaryOverlay['outside']);
    $lines[] = '';
    $lines[] = fields('probability', $selected['model']->kernel['name'], 'A', fixed($calibration['A'], 6), 'B', fixed($calibration['B'], 6));
    foreach (frame_grid($probabilityGrid, $W) as $line) $lines[] = $line;
    $lines[] = 'levels ' . implode(' ', $levels);
    $lines[] = '';
    $lines[] = 'grid_agreement';
    for ($a = 0; $a < count($finals); $a++) for ($b = $a + 1; $b < count($finals); $b++) {
        $agreement = 0; $positiveA = 0; $positiveB = 0;
        for ($cell = 0; $cell < $W * $H; $cell++) {
            if ($signs[$a][$cell] === $signs[$b][$cell]) $agreement++;
            if ($signs[$a][$cell] === 1) $positiveA++;
            if ($signs[$b][$cell] === 1) $positiveB++;
        }
        $lines[] = fields($finals[$a]['model']->kernel['name'], $finals[$b]['model']->kernel['name'], $agreement . '/' . ($W * $H), 'positive', $positiveA, $positiveB);
    }
    $lines[] = '';
    $lines[] = fields('multiclass', $multiKernel['name'], 'C', fixed($params['multiC'], 4));
    foreach (frame_grid($multiGrid, $W) as $line) $lines[] = $line;
    $lines[] = fields('cells class1', grid_count($multiGrid, ' '), 'class2', grid_count($multiGrid, '.'), 'class3', grid_count($multiGrid, ':'),
        'disagree', grid_count($multiGrid, '?'), 'points', $multiOverlay['points'], 'outside', $multiOverlay['outside']);
    return $lines;
}

function main()
{
    $data = read_dataset();
    $train = $data['train']; $test = $data['test']; $multiTrain = $data['multiTrain']; $multiTest = $data['multiTest']; $params = $data['params'];
    $points = array_column($train, 'point'); $labels = array_column($train, 'label');
    $matrices = [];
    foreach ($params['kernels'] as $kernel) $matrices[] = kernel_matrix($kernel, $points);
    $cv = cross_validate($train, $params, $matrices);
    $finals = [];
    foreach ($params['kernels'] as $kernel) {
        $model = smo_train($points, $labels, $matrices[$kernel['index']], $cv['best'][$kernel['index']]['C'], $kernel, $params);
        $finals[] = measure($model, $test);
    }
    $blocks = [cross_validation_lines($cv, count($train), $params)];
    foreach ($finals as &$result) $blocks[] = final_model_lines($result, $train, $test, $params);
    unset($result);
    $selected = $finals[$cv['selected']['kernel']['index']];
    foreach (selected_analyses($selected, $train, $test, $params) as $block) $blocks[] = $block;
    $calibration = calibrate($cv['selected'], $selected, $train, $test, $params);
    $blocks[] = $calibration['lines'];
    $comparison = null;
    foreach ($finals as $result) if ($result['model']->kernel['kind'] === 'linear') { $comparison = $result; break; }
    $peg = pegasos($train, $test, $comparison, $params);
    $blocks[] = $peg['lines'];
    $blocks[] = mcnemar($finals, $peg, $test);
    $modelLines = [];
    foreach ($blocks as $block) {
        if (count($modelLines) > 0) $modelLines[] = '';
        foreach ($block as $line) $modelLines[] = $line;
    }
    write_output('model.txt', $modelLines);
    $header = ['kernel', 'C'];
    for ($i = 1; $i <= $params['folds']; $i++) $header[] = 'fold' . $i;
    $grid = [implode(',', array_merge($header, ['correct', 'accuracy', 'support_vectors', 'passes', 'steps']))];
    foreach ($cv['combinations'] as $entry) {
        $line = [$entry['kernel']['name'], fixed($entry['C'], 4)];
        foreach ($entry['folds'] as $fold) $line[] = $fold['correct'];
        $line = array_merge($line, [$entry['correct'], ratio($entry['correct'], count($train)), $entry['support'], $entry['passes'], $entry['steps']]);
        $grid[] = implode(',', $line);
    }
    write_output('cv_grid.csv', $grid);
    $header = ['id', 'label'];
    foreach ($params['kernels'] as $kernel) $header[] = $kernel['name'];
    $predictions = [implode(',', array_merge($header, ['pegasos', 'predicted', 'probability']))];
    foreach ($test as $i => $row) {
        $line = [$row['id'], $row['label']];
        foreach ($finals as $result) $line[] = fixed($result['testValues'][$i], 4);
        $line[] = fixed($peg['values'][$i], 4);
        $line[] = sign_value($selected['testValues'][$i]);
        $line[] = fixed($calibration['probabilities'][$i], 4);
        $predictions[] = implode(',', $line);
    }
    write_output('predictions.csv', $predictions);
    $multiKernel = null;
    foreach ($params['kernels'] as $kernel) if ($kernel['name'] === $params['multiName']) { $multiKernel = $kernel; break; }
    $multiModels = multiclass_train($multiTrain, $multiKernel, $params['multiC'], $params);
    write_output('multiclass.txt', multiclass_lines($multiModels, $multiTrain, $multiTest, $multiKernel, $params));
    write_output('decision_plot.txt', decision_plots($finals, $selected, $calibration, $multiModels, $multiKernel, $train, $multiTrain, $params));
}

main();
