<?php

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/stumps.php';
require_once __DIR__ . '/adaboost.php';
require_once __DIR__ . '/variants.php';
require_once __DIR__ . '/evaluation.php';

class Minstd
{
    private $state;

    public function __construct($seed) { $this->state = $seed; }

    public function next()
    {
        $this->state = (48271 * $this->state) % 2147483647;
        return $this->state;
    }
}

function fields(...$values)
{
    return implode(' ', $values);
}

function total($values)
{
    $result = 0;
    foreach ($values as $value) $result += $value;
    return $result;
}

function fixed_values($values)
{
    return implode(' ', array_map('fixed', $values));
}

function train_variant($name, $rows, $params)
{
    if ($name === 'discrete') return discrete($rows, $params['rounds']);
    if ($name === 'real') return real_boost($rows, $params);
    if ($name === 'gentle') return gentle($rows, $params);
    return logit($rows, $params);
}

function score($rounds, $values)
{
    $result = 0.0;
    foreach ($rounds as $round) $result += $round['stump']->output($values);
    return $result;
}

function score_rows($rounds, $rows)
{
    $result = [];
    foreach ($rows as $row) $result[] = score($rounds, $row['values']);
    return $result;
}

function magnitude($round)
{
    $maximum = 0.0;
    foreach ($round['stump']->values as $value) $maximum = max($maximum, abs($value));
    return $maximum;
}

function error_count($rows, $scores)
{
    $errors = 0;
    foreach ($rows as $i => $row) if (prediction($scores[$i]) !== $row['label']) $errors++;
    return $errors;
}

function loss($rows, $scores, $variant)
{
    $total = 0.0;
    foreach ($rows as $i => $row) {
        $total += $variant === 'logit' ? log(1 + exp(-2 * $row['label'] * $scores[$i])) : exp(-$row['label'] * $scores[$i]);
    }
    return $total / count($rows);
}

function minimum_position($values)
{
    $best = 0;
    for ($i = 1; $i < count($values); $i++) if ($values[$i] < $values[$best]) $best = $i;
    return $best;
}

function curve($rounds, $train, $test, $variant)
{
    $trainScores = array_fill(0, count($train), 0.0);
    $testScores = array_fill(0, count($test), 0.0);
    $scale = 0.0;
    $result = [];
    foreach ($rounds as $round) {
        foreach ($train as $i => $row) $trainScores[$i] += $round['stump']->output($row['values']);
        foreach ($test as $i => $row) $testScores[$i] += $round['stump']->output($row['values']);
        $scale += magnitude($round);
        $margins = [];
        foreach ($train as $i => $row) $margins[] = $row['label'] * $trainScores[$i];
        $result[] = ['trainErrors' => error_count($train, $trainScores), 'testErrors' => error_count($test, $testScores),
            'trainLoss' => loss($train, $trainScores, $variant), 'testLoss' => loss($test, $testScores, $variant), 'minimum' => min($margins) / $scale];
    }
    return $result;
}

function cross_validation($rows, $params)
{
    $folds = [];
    for ($fold = 0; $fold < $params['folds']; $fold++) {
        $validation = [];
        foreach ($rows as $i => $row) if ($i % $params['folds'] === $fold) $validation[] = $i;
        $count = count($rows) - count($validation);
        $weights = [];
        foreach ($rows as $i => $row) $weights[] = $i % $params['folds'] === $fold ? 0.0 : 1 / $count;
        $model = discrete($rows, $params['rounds'], 1, $weights);
        $scores = array_fill(0, count($validation), 0.0);
        $errors = [];
        for ($t = 0; $t < $params['rounds']; $t++) {
            if ($t < count($model['rounds'])) foreach ($validation as $i => $index) {
                $scores[$i] += $model['rounds'][$t]['stump']->output($rows[$index]['values']);
            }
            $countErrors = 0;
            foreach ($validation as $i => $index) if (prediction($scores[$i]) !== $rows[$index]['label']) $countErrors++;
            $errors[] = $countErrors;
        }
        $folds[] = compact('model', 'validation', 'count', 'errors');
    }
    $errors = array_fill(0, $params['rounds'], 0);
    foreach ($folds as $fold) for ($t = 0; $t < $params['rounds']; $t++) $errors[$t] += $fold['errors'][$t];
    $selected = minimum_position($errors) + 1;
    $scores = array_fill(0, count($rows), 0.0);
    foreach ($folds as $fold) {
        $rounds = array_slice($fold['model']['rounds'], 0, $selected);
        foreach ($fold['validation'] as $i) $scores[$i] = score($rounds, $rows[$i]['values']);
    }
    return compact('folds', 'errors', 'selected', 'scores');
}

function importance($rounds, $featureCount, $multiclass = false)
{
    $features = [];
    for ($j = 0; $j < $featureCount; $j++) $features[] = ['feature' => $j, 'score' => 0.0, 'count' => 0];
    foreach ($rounds as $round) {
        $j = $round['stump']->feature;
        $features[$j]['score'] += $multiclass ? $round['alpha'] : magnitude($round);
        $features[$j]['count']++;
    }
    $sum = 0.0;
    foreach ($features as $item) $sum += $item['score'];
    foreach ($features as &$item) $item['share'] = $item['score'] / $sum;
    unset($item);
    usort($features, fn($a, $b) => ($b['score'] <=> $a['score']) ?: ($a['feature'] <=> $b['feature']));
    return $features;
}

function analyze_models($data, $cv)
{
    $models = [];
    foreach ($data['params']['variants'] as $name) {
        $full = train_variant($name, $data['train'], $data['params']);
        $rounds = $name === 'discrete' ? array_slice($full['rounds'], 0, $cv['selected']) : $full['rounds'];
        $scale = 0.0;
        foreach ($rounds as $round) $scale += magnitude($round);
        $trainScores = score_rows($rounds, $data['train']);
        $testScores = score_rows($rounds, $data['test']);
        $trainMargins = [];
        $testMargins = [];
        foreach ($data['train'] as $i => $row) $trainMargins[] = $row['label'] * $trainScores[$i] / $scale;
        foreach ($data['test'] as $i => $row) $testMargins[] = $row['label'] * $testScores[$i] / $scale;
        $models[] = ['name' => $name, 'full' => $full, 'rounds' => $rounds, 'scale' => $scale,
            'trainScores' => $trainScores, 'testScores' => $testScores, 'trainMargins' => $trainMargins, 'testMargins' => $testMargins,
            'trainPredictions' => array_map('prediction', $trainScores), 'testPredictions' => array_map('prediction', $testScores),
            'curve' => curve($full['rounds'], $data['train'], $data['test'], $name), 'importance' => importance($rounds, count($data['features']))];
    }
    return $models;
}

function ensemble_lines($data, $models, $cv)
{
    $lines = [];
    foreach ($models as $model) {
        if (count($lines) > 0) $lines[] = '';
        $name = $model['name'];
        $full = $model['full'];
        $heading = fields('variant', $name, 'rounds', count($full['rounds']), 'stop', $full['stop']);
        if ($name === 'real') $heading .= ' ' . fields('bins', $data['params']['bins'], 'smoothing', fixed($data['params']['smoothing']), 'convergence', fixed($data['params']['convergence'], 6));
        if ($name === 'logit') $heading .= ' clip ' . fixed($data['params']['clip']);
        $lines[] = $heading;
        if ($name === 'real') foreach ($data['features'] as $j => $feature) $lines[] = fields('cuts', $feature, fixed_values($full['cuts'][$j]));
        foreach ($full['rounds'] as $t => $round) {
            $stump = $round['stump'];
            $prefix = fields('round', $t + 1, 'feature', $data['features'][$stump->feature]);
            if ($name === 'discrete') {
                $lines[] = $prefix . ' ' . fields('threshold', fixed($stump->thresholds[0]), 'polarity', $round['polarity'],
                    'error', fixed($round['error']), 'alpha', fixed($round['alpha']), 'z', fixed($round['z']), 'bound', fixed($round['bound']));
                $maximum = 0;
                $squares = 0.0;
                foreach ($round['weights'] as $i => $weight) {
                    if ($weight > $round['weights'][$maximum]) $maximum = $i;
                    $squares += $weight * $weight;
                }
                $lines[] = fields('weights', $t + 1, 'max', fixed($round['weights'][$maximum], 6), 'id', $data['train'][$maximum]['id'], 'ess', fixed(1 / $squares));
            } elseif ($name === 'real') {
                $lines[] = $prefix . ' ' . fields('z', fixed($round['z']), 'bound', fixed($round['bound']), 'values', fixed_values($stump->values));
            } else {
                $line = $prefix . ' ' . fields('threshold', fixed($stump->thresholds[0]), 'left', fixed($stump->values[0]), 'right', fixed($stump->values[1]), 'error', fixed($round['error']));
                if ($name === 'logit') $line .= ' loss ' . fixed($round['loss']);
                $lines[] = $line;
            }
        }
        if ($name === 'discrete') {
            $lines[] = fields('cv folds', $data['params']['folds'], 'selected', $cv['selected'], 'errors', $cv['errors'][$cv['selected'] - 1] . '/' . count($data['train']));
            foreach ($cv['folds'] as $f => $fold) {
                $size = count($fold['validation']);
                $lines[] = fields('fold', $f + 1, 'train', $fold['count'], 'validation', $size, 'rounds', count($fold['model']['rounds']),
                    'stop', $fold['model']['stop'], 'selected', $fold['errors'][$cv['selected'] - 1] . '/' . $size,
                    'final', $fold['errors'][count($fold['errors']) - 1] . '/' . $size);
            }
            $lines[] = 'cv_errors ' . implode(' ', $cv['errors']);
        }
    }
    return $lines;
}

function error_curve_lines($data, $models, $multi)
{
    $lines = ['variant,round,train_error,test_error,train_loss,test_loss,min_margin'];
    foreach ($models as $model) foreach ($model['curve'] as $t => $row) {
        $lines[] = implode(',', [$model['name'], $t + 1, ratio($row['trainErrors'], count($data['train'])), ratio($row['testErrors'], count($data['test'])),
            fixed($row['trainLoss']), fixed($row['testLoss']), fixed($row['minimum'])]);
    }
    foreach ($multi['curve'] as $t => $row) {
        $lines[] = implode(',', ['samme', $t + 1, ratio($row['train'], count($data['multiTrain'])), ratio($row['test'], count($data['multiTest'])), '-', '-', '-']);
    }
    return $lines;
}

function prediction_lines($data, $models)
{
    $lines = ['id,variant,score,label,' . implode(',', $data['features'])];
    foreach ($data['test'] as $i => $row) foreach ($models as $model) {
        $contributions = array_fill(0, count($data['features']), 0.0);
        foreach ($model['rounds'] as $round) $contributions[$round['stump']->feature] += $round['stump']->output($row['values']);
        $lines[] = implode(',', array_merge([$row['id'], $model['name'], fixed($model['testScores'][$i]), $model['testPredictions'][$i]], array_map('fixed', $contributions)));
    }
    return $lines;
}

function distinct_numbers($values, $descending = false)
{
    if ($descending) rsort($values, SORT_NUMERIC);
    else sort($values, SORT_NUMERIC);
    $distinct = [];
    foreach ($values as $value) if (count($distinct) === 0 || $value != $distinct[count($distinct) - 1]) $distinct[] = $value;
    return $distinct;
}

function roc_lines($data, $models)
{
    $lines = ['variant,threshold,tp,fp'];
    foreach ($models as $model) foreach (distinct_numbers($model['testScores'], true) as $threshold) {
        $tp = 0;
        $fp = 0;
        foreach ($data['test'] as $i => $row) {
            if ($model['testScores'][$i] < $threshold) continue;
            if ($row['label'] === 1) $tp++;
            else $fp++;
        }
        $lines[] = implode(',', [$model['name'], fixed($threshold), $tp, $fp]);
    }
    return $lines;
}

function importance_lines($items, $names)
{
    $lines = [];
    foreach ($items as $i => $item) $lines[] = fields($i + 1, $names[$item['feature']], 'score', fixed($item['score']), 'share', fixed($item['share']), 'rounds', $item['count']);
    return $lines;
}

function permutation_importance($model, $rows, $featureCount, $repeats, $generator)
{
    $base = count($rows) - error_count($rows, $model['testScores']);
    $results = [];
    for ($feature = 0; $feature < $featureCount; $feature++) {
        $counts = [];
        $drop = 0;
        for ($r = 0; $r < $repeats; $r++) {
            $permutation = range(0, count($rows) - 1);
            for ($i = count($rows) - 1; $i >= 1; $i--) {
                $other = $generator->next() % ($i + 1);
                [$permutation[$i], $permutation[$other]] = [$permutation[$other], $permutation[$i]];
            }
            $correct = 0;
            foreach ($rows as $i => $row) {
                $values = $row['values'];
                $values[$feature] = $rows[$permutation[$i]]['values'][$feature];
                if (prediction(score($model['rounds'], $values)) === $row['label']) $correct++;
            }
            $counts[] = $correct;
            $drop += $base - $correct;
        }
        $results[] = ['feature' => $feature, 'drop' => $drop, 'minimum' => min($counts), 'maximum' => max($counts)];
    }
    usort($results, fn($a, $b) => ($b['drop'] <=> $a['drop']) ?: ($a['feature'] <=> $b['feature']));
    return compact('base', 'results');
}

function margin_lines($data, $models)
{
    $lines = [];
    $generator = new Minstd($data['params']['permutationSeed']);
    foreach ($models as $model) {
        if (count($lines) > 0) $lines[] = '';
        $lines[] = fields('variant', $model['name'], 'rounds', count($model['rounds']), 'scale', fixed($model['scale']));
        $lines[] = fields('train min', fixed(min($model['trainMargins'])), 'mean', fixed(total($model['trainMargins']) / count($data['train'])));
        foreach ($data['params']['margins'] as $threshold) {
            $count = count_at_most($model['trainMargins'], $threshold);
            $lines[] = fields('train le', fixed($threshold), $count . '/' . count($data['train']), ratio($count, count($data['train'])));
        }
        $histogram = array_fill(0, 20, 0);
        foreach ($model['trainMargins'] as $margin) $histogram[min(19, (int) floor(($margin + 1) * 10))]++;
        $lines[] = 'histogram ' . implode(' ', $histogram);
        $hardest = range(0, count($data['train']) - 1);
        usort($hardest, fn($a, $b) => ($model['trainMargins'][$a] <=> $model['trainMargins'][$b]) ?: ($a <=> $b));
        foreach (array_slice($hardest, 0, 5) as $i) $lines[] = fields('hardest', $data['train'][$i]['id'], 'label', $data['train'][$i]['label'], 'margin', fixed($model['trainMargins'][$i]));
        $lines[] = fields('test min', fixed(min($model['testMargins'])), 'mean', fixed(total($model['testMargins']) / count($data['test'])));
        foreach ($data['params']['margins'] as $threshold) {
            $count = count_at_most($model['testMargins'], $threshold);
            $lines[] = fields('test le', fixed($threshold), $count . '/' . count($data['test']), ratio($count, count($data['test'])));
        }
        foreach ($data['params']['margins'] as $threshold) {
            $count = 0;
            $correct = 0;
            foreach ($data['test'] as $i => $row) {
                if (abs($model['testMargins'][$i]) <= $threshold) continue;
                $count++;
                if ($model['testPredictions'][$i] === $row['label']) $correct++;
            }
            $lines[] = fields('test confident', fixed($threshold), $count . '/' . count($data['test']), 'correct', $correct . '/' . $count, ratio($correct, $count));
        }
        $lines[] = 'importance';
        foreach (importance_lines($model['importance'], $data['features']) as $line) $lines[] = $line;
        $permutation = permutation_importance($model, $data['test'], count($data['features']), $data['params']['permutationRepeats'], $generator);
        $lines[] = fields('permutation repeats', $data['params']['permutationRepeats'], 'base', $permutation['base'] . '/' . count($data['test']));
        foreach ($permutation['results'] as $i => $item) {
            $lines[] = fields($i + 1, $data['features'][$item['feature']], 'drop', ratio($item['drop'], $data['params']['permutationRepeats'] * count($data['test'])),
                'min', $item['minimum'] . '/' . count($data['test']), 'max', $item['maximum'] . '/' . count($data['test']));
        }
    }
    return $lines;
}

function shape_lines($data, $models)
{
    $lines = [];
    foreach ($models as $model) {
        if (count($lines) > 0) $lines[] = '';
        $lines[] = fields('variant', $model['name'], 'rounds', count($model['rounds']));
        foreach ($data['features'] as $feature => $name) {
            $rounds = [];
            $cuts = [];
            foreach ($model['rounds'] as $round) if ($round['stump']->feature === $feature) {
                $rounds[] = $round;
                foreach ($round['stump']->thresholds as $threshold) $cuts[] = $threshold;
            }
            $thresholds = distinct_numbers($cuts);
            $values = [];
            for ($interval = 0; $interval <= count($thresholds); $interval++) {
                $sum = 0.0;
                foreach ($rounds as $round) {
                    $bin = 0;
                    if ($interval > 0) foreach ($round['stump']->thresholds as $threshold) if ($threshold <= $thresholds[$interval - 1]) $bin++;
                    $sum += $round['stump']->values[$bin];
                }
                $values[] = $sum;
            }
            $lines[] = fields('feature', $name, 'rounds', count($rounds), 'cuts', count($thresholds), 'range', fixed(max($values) - min($values)));
            foreach ($values as $i => $value) {
                $lower = $i === 0 ? '-inf' : fixed($thresholds[$i - 1]);
                $upper = $i === count($thresholds) ? 'inf' : fixed($thresholds[$i]);
                $lines[] = fields('interval', $lower, $upper, 'value', fixed($value));
            }
        }
    }
    return $lines;
}

function metrics_line($kind, $variant, $rounds, $rows, $scores)
{
    $tp = 0;
    $fp = 0;
    $tn = 0;
    $fn = 0;
    foreach ($rows as $i => $row) {
        $predicted = prediction($scores[$i]);
        if ($row['label'] === 1) {
            if ($predicted === 1) $tp++;
            else $fn++;
        } elseif ($predicted === 1) $fp++;
        else $tn++;
    }
    return fields($kind, $variant, 'rounds', $rounds, 'correct', ($tp + $tn) . '/' . count($rows), 'accuracy', ratio($tp + $tn, count($rows)),
        'tp', $tp, 'fp', $fp, 'tn', $tn, 'fn', $fn, 'precision', ratio($tp, $tp + $fp), 'recall', ratio($tp, $tp + $fn),
        'f1', ratio(2 * $tp, 2 * $tp + $fp + $fn), 'auc', auc($rows, $scores), 'loss', fixed(loss($rows, $scores, $variant)));
}

function feature_summary($rows, $feature)
{
    $values = [];
    foreach ($rows as $row) $values[] = $row['values'][$feature];
    return fields(fixed(min($values)), fixed(max($values)), fixed(total($values) / count($values)), count(distinct_numbers($values)));
}

function variant_pairs($models)
{
    $pairs = [];
    for ($a = 0; $a < count($models); $a++) for ($b = $a + 1; $b < count($models); $b++) $pairs[] = [$a, $b];
    return $pairs;
}

function bootstrap_lines($data, $models)
{
    $samples = $data['params']['bootstrapSamples'];
    $seed = $data['params']['bootstrapSeed'];
    $generator = new Minstd($seed);
    $counts = array_fill(0, count($models), []);
    for ($sample = 0; $sample < $samples; $sample++) {
        $selected = [];
        foreach ($data['test'] as $row) $selected[] = $generator->next() % count($data['test']);
        foreach ($models as $v => $model) {
            $correct = 0;
            foreach ($selected as $i) if ($model['testPredictions'][$i] === $data['test'][$i]['label']) $correct++;
            $counts[$v][] = $correct;
        }
    }
    $lines = [fields('bootstrap samples', $samples, 'seed', $seed)];
    $tail = intdiv($samples, 40);
    foreach ($models as $v => $model) {
        $sorted = $counts[$v];
        sort($sorted, SORT_NUMERIC);
        $lines[] = fields($model['name'], 'mean', ratio(total($counts[$v]), $samples * count($data['test'])),
            'low', ratio($sorted[$tail], count($data['test'])), 'high', ratio($sorted[$samples - $tail - 1], count($data['test'])));
    }
    foreach (variant_pairs($models) as [$a, $b]) {
        $first = 0;
        $tie = 0;
        $second = 0;
        for ($i = 0; $i < $samples; $i++) {
            if ($counts[$a][$i] > $counts[$b][$i]) $first++;
            elseif ($counts[$a][$i] < $counts[$b][$i]) $second++;
            else $tie++;
        }
        $lines[] = fields($models[$a]['name'], $models[$b]['name'], 'first', $first, 'tie', $tie, 'second', $second);
    }
    return $lines;
}

function calibration_lines($data, $models)
{
    $lines = [];
    $ranges = ['0.0-0.2', '0.2-0.4', '0.4-0.6', '0.6-0.8', '0.8-1.0'];
    foreach ($models as $model) {
        $bins = array_fill(0, 5, ['count' => 0, 'probability' => 0.0, 'positive' => 0]);
        $brier = 0.0;
        foreach ($data['test'] as $i => $row) {
            $probability = 1 / (1 + exp(-2 * $model['testScores'][$i]));
            $target = $row['label'] === 1 ? 1 : 0;
            $brier += ($probability - $target) * ($probability - $target);
            $bin = min(4, (int) floor($probability * 5));
            $bins[$bin]['count']++;
            $bins[$bin]['probability'] += $probability;
            $bins[$bin]['positive'] += $target;
        }
        $lines[] = fields('calibration', $model['name'], 'brier', fixed($brier / count($data['test'])));
        foreach ($bins as $i => $bin) $lines[] = fields('bin', $ranges[$i], 'count', $bin['count'], 'mean', ratio($bin['probability'], $bin['count']), 'positives', $bin['positive']);
    }
    return $lines;
}

function summary_lines($data, $models, $cv)
{
    $positives = function ($rows) {
        $count = 0;
        foreach ($rows as $row) if ($row['label'] === 1) $count++;
        return $count;
    };
    $lines = [fields('data train', count($data['train']), 'test', count($data['test']), 'features', count($data['features']),
        'positives', $positives($data['train']), $positives($data['test']))];
    foreach ($data['features'] as $j => $feature) $lines[] = fields('feature', $feature, 'train', feature_summary($data['train'], $j), 'test', feature_summary($data['test'], $j));
    $lines[] = fields('cv selected', $cv['selected'], 'errors', $cv['errors'][$cv['selected'] - 1] . '/' . count($data['train']), 'rate', ratio($cv['errors'][$cv['selected'] - 1], count($data['train'])));
    $lines[] = metrics_line('oof', 'discrete', $cv['selected'], $data['train'], $cv['scores']);
    foreach ($models as $model) {
        $lines[] = metrics_line('train', $model['name'], count($model['rounds']), $data['train'], $model['trainScores']);
        $lines[] = metrics_line('test', $model['name'], count($model['rounds']), $data['test'], $model['testScores']);
    }
    $committeeRounds = 0;
    foreach ($models as $model) $committeeRounds += count($model['rounds']);
    foreach (['train', 'test'] as $kind) {
        $rows = $data[$kind];
        $scores = [];
        foreach ($rows as $i => $row) {
            $sum = 0.0;
            foreach ($models as $model) $sum += $model[$kind . 'Scores'][$i] / $model['scale'];
            $scores[] = $sum;
        }
        $lines[] = metrics_line($kind, 'committee', $committeeRounds, $rows, $scores);
    }
    foreach ($models as $model) {
        $trainMinimum = minimum_position(array_column($model['curve'], 'trainErrors'));
        $testMinimum = minimum_position(array_column($model['curve'], 'testErrors'));
        $lines[] = fields('curve', $model['name'], 'rounds', count($model['full']['rounds']), 'train_min',
            $model['curve'][$trainMinimum]['trainErrors'] . '/' . count($data['train']), 'at', $trainMinimum + 1,
            'test_min', $model['curve'][$testMinimum]['testErrors'] . '/' . count($data['test']), 'at', $testMinimum + 1);
    }
    $wrong = [];
    foreach ($data['test'] as $i => $row) {
        $allWrong = true;
        foreach ($models as $model) if ($model['testPredictions'][$i] === $row['label']) { $allWrong = false; break; }
        if ($allWrong) $wrong[] = $row['id'];
    }
    $lines[] = implode(' ', array_merge(['all_wrong', count($wrong)], $wrong));
    $lines[] = 'agreement';
    foreach (variant_pairs($models) as [$a, $b]) {
        $agree = 0;
        $first = 0;
        $second = 0;
        foreach ($data['test'] as $i => $row) {
            $left = $models[$a]['testPredictions'][$i];
            $right = $models[$b]['testPredictions'][$i];
            if ($left === $right) $agree++;
            if ($left === $row['label'] && $right !== $row['label']) $first++;
            if ($right === $row['label'] && $left !== $row['label']) $second++;
        }
        $difference = abs($first - $second) - 1;
        $lines[] = fields($models[$a]['name'], $models[$b]['name'], 'agree', $agree . '/' . count($data['test']), 'only_first', $first,
            'only_second', $second, 'chi2', ratio($difference * $difference, $first + $second));
    }
    foreach (bootstrap_lines($data, $models) as $line) $lines[] = $line;
    foreach (calibration_lines($data, $models) as $line) $lines[] = $line;
    return $lines;
}

function class_prediction($scores)
{
    return largest_index($scores) + 1;
}

function multiclass_errors($rows, $predictions)
{
    $errors = 0;
    foreach ($rows as $i => $row) if ($predictions[$i] !== $row['category']) $errors++;
    return $errors;
}

function multiclass_analysis($data)
{
    $train = $data['multiTrain'];
    $test = $data['multiTest'];
    $params = $data['params'];
    $model = samme($train, $params['classes'], $params['sammeRounds']);
    $trainScores = array_fill(0, count($train), array_fill(0, $params['classes'], 0.0));
    $testScores = array_fill(0, count($test), array_fill(0, $params['classes'], 0.0));
    $progress = [];
    foreach ($model['rounds'] as $round) {
        foreach ($train as $i => $row) $trainScores[$i][$round['stump']->output($row['values']) - 1] += $round['alpha'];
        foreach ($test as $i => $row) $testScores[$i][$round['stump']->output($row['values']) - 1] += $round['alpha'];
        $progress[] = ['train' => multiclass_errors($train, array_map('class_prediction', $trainScores)),
            'test' => multiclass_errors($test, array_map('class_prediction', $testScores))];
    }
    $ovr = [];
    for ($category = 1; $category <= $params['classes']; $category++) {
        $binaryTrain = [];
        $binaryTest = [];
        $positives = 0;
        foreach ($train as $row) {
            $row['label'] = $row['category'] === $category ? 1 : -1;
            if ($row['label'] === 1) $positives++;
            $binaryTrain[] = $row;
        }
        foreach ($test as $row) {
            $row['label'] = $row['category'] === $category ? 1 : -1;
            $binaryTest[] = $row;
        }
        $binaryModel = discrete($binaryTrain, $params['sammeRounds']);
        $trainValues = score_rows($binaryModel['rounds'], $binaryTrain);
        $testValues = score_rows($binaryModel['rounds'], $binaryTest);
        $ovr[] = ['model' => $binaryModel, 'trainScores' => $trainValues, 'testScores' => $testValues, 'positives' => $positives,
            'trainErrors' => error_count($binaryTrain, $trainValues), 'testErrors' => error_count($binaryTest, $testValues)];
    }
    $ovrTrain = [];
    foreach ($train as $i => $row) {
        $scores = [];
        foreach ($ovr as $item) $scores[] = $item['trainScores'][$i];
        $ovrTrain[] = class_prediction($scores);
    }
    $ovrTest = [];
    foreach ($test as $i => $row) {
        $scores = [];
        foreach ($ovr as $item) $scores[] = $item['testScores'][$i];
        $ovrTest[] = class_prediction($scores);
    }
    return ['model' => $model, 'curve' => $progress, 'trainScores' => $trainScores, 'testScores' => $testScores, 'ovr' => $ovr,
        'trainPredictions' => array_map('class_prediction', $trainScores), 'testPredictions' => array_map('class_prediction', $testScores),
        'ovrTrain' => $ovrTrain, 'ovrTest' => $ovrTest];
}

function confusion_lines($rows, $predictions, $classes)
{
    $matrix = confusion($rows, $predictions, $classes);
    $lines = ['confusion'];
    foreach ($matrix as $row) $lines[] = implode(' ', $row);
    for ($c = 0; $c < $classes; $c++) {
        $column = 0;
        foreach ($matrix as $row) $column += $row[$c];
        $lines[] = fields('class', $c + 1, 'precision', ratio($matrix[$c][$c], $column), 'recall', ratio($matrix[$c][$c], total($matrix[$c])));
    }
    return $lines;
}

function multiclass_evaluation_lines($data, $trainPredictions, $testPredictions)
{
    $trainErrors = multiclass_errors($data['multiTrain'], $trainPredictions);
    $testErrors = multiclass_errors($data['multiTest'], $testPredictions);
    return array_merge([fields('train errors', $trainErrors . '/' . count($data['multiTrain']), 'rate', ratio($trainErrors, count($data['multiTrain']))),
        fields('test errors', $testErrors . '/' . count($data['multiTest']), 'rate', ratio($testErrors, count($data['multiTest'])))],
        confusion_lines($data['multiTest'], $testPredictions, $data['params']['classes']));
}

function samme_lines($data, $multi)
{
    $model = $multi['model'];
    $lines = [fields('samme classes', $data['params']['classes'], 'train', count($data['multiTrain']), 'test', count($data['multiTest']),
        'rounds', count($model['rounds']), 'stop', $model['stop'])];
    foreach ($model['rounds'] as $t => $round) {
        $stump = $round['stump'];
        $lines[] = fields('round', $t + 1, 'feature', $data['multiFeatures'][$stump->feature], 'threshold', fixed($stump->thresholds[0]),
            'left', $stump->values[0], 'right', $stump->values[1], 'error', fixed($round['error']), 'alpha', fixed($round['alpha']));
    }
    foreach (multiclass_evaluation_lines($data, $multi['trainPredictions'], $multi['testPredictions']) as $line) $lines[] = $line;
    $lines[] = 'importance';
    foreach (importance_lines(importance($model['rounds'], count($data['multiFeatures']), true), $data['multiFeatures']) as $line) $lines[] = $line;
    $lines[] = '';
    $lines[] = fields('ovr classes', $data['params']['classes'], 'rounds', $data['params']['sammeRounds']);
    foreach ($multi['ovr'] as $c => $item) {
        $lines[] = fields('class', $c + 1, 'rounds', count($item['model']['rounds']), 'stop', $item['model']['stop'], 'positives', $item['positives'],
            'train_errors', $item['trainErrors'] . '/' . count($data['multiTrain']), 'test_errors', $item['testErrors'] . '/' . count($data['multiTest']));
    }
    foreach (multiclass_evaluation_lines($data, $multi['ovrTrain'], $multi['ovrTest']) as $line) $lines[] = $line;
    $agree = 0;
    foreach ($data['multiTest'] as $i => $row) if ($multi['testPredictions'][$i] === $multi['ovrTest'][$i]) $agree++;
    $lines[] = 'agreement ' . $agree . '/' . count($data['multiTest']);
    $lines[] = '';
    $lines[] = 'predictions';
    foreach ($data['multiTest'] as $i => $row) {
        $lines[] = fields($row['id'], 'class', $row['category'], 'samme', $multi['testPredictions'][$i], 'ovr', $multi['ovrTest'][$i], 'scores', fixed_values($multi['testScores'][$i]));
    }
    return $lines;
}

function experiment_stats($model, $train, $test)
{
    $trainErrors = error_count($train, score_rows($model['rounds'], $train));
    $testScores = array_fill(0, count($test), 0.0);
    $testErrors = [];
    foreach ($model['rounds'] as $round) {
        foreach ($test as $i => $row) $testScores[$i] += $round['stump']->output($row['values']);
        $testErrors[] = error_count($test, $testScores);
    }
    $minimum = minimum_position($testErrors);
    return ['trainErrors' => $trainErrors, 'testErrors' => $testErrors[count($testErrors) - 1], 'minimum' => $testErrors[$minimum], 'at' => $minimum + 1];
}

function experiment_fields($model, $stats, $trainCount, $testCount)
{
    return fields('rounds', count($model['rounds']), 'stop', $model['stop'], 'train_errors', $stats['trainErrors'] . '/' . $trainCount,
        'test_errors', $stats['testErrors'] . '/' . $testCount);
}

function experiment_lines($data, $models, $cv)
{
    $train = $data['train'];
    $test = $data['test'];
    $params = $data['params'];
    $lines = [];
    foreach ($params['sizes'] as $percentage) {
        $count = intdiv(count($train) * $percentage, 100);
        $selected = array_slice($train, 0, $count);
        $lines[] = fields('size', $percentage, 'rows', $count);
        foreach ($params['variants'] as $variant) {
            $model = train_variant($variant, $selected, $params);
            $lines[] = $variant . ' ' . experiment_fields($model, experiment_stats($model, $selected, $test), $count, count($test));
        }
    }
    foreach ($params['shrinkage'] as $shrinkage) {
        $model = discrete($train, $params['rounds'], $shrinkage);
        $stats = experiment_stats($model, $train, $test);
        $lines[] = fields('shrinkage', fixed($shrinkage), experiment_fields($model, $stats, count($train), count($test)),
            'test_min', $stats['minimum'] . '/' . count($test), 'at', $stats['at']);
    }
    $ranks = [];
    foreach ($models as $model) if ($model['name'] === 'discrete') { $ranks = $model['importance']; break; }
    for ($count = 1; $count <= count($data['features']); $count++) {
        $features = [];
        foreach (array_slice($ranks, 0, $count) as $item) $features[] = $item['feature'];
        sort($features, SORT_NUMERIC);
        $project = function ($rows) use ($features) {
            $result = [];
            foreach ($rows as $row) {
                $values = [];
                foreach ($features as $feature) $values[] = $row['values'][$feature];
                $row['values'] = $values;
                $result[] = $row;
            }
            return $result;
        };
        $reducedTrain = $project($train);
        $reducedTest = $project($test);
        $model = discrete($reducedTrain, $cv['selected']);
        $stats = experiment_stats($model, $reducedTrain, $reducedTest);
        $names = [];
        foreach ($features as $feature) $names[] = $data['features'][$feature];
        $lines[] = fields('top', $count, 'features', implode(' ', $names), 'rounds', count($model['rounds']),
            'train_errors', $stats['trainErrors'] . '/' . count($train), 'test_errors', $stats['testErrors'] . '/' . count($test));
    }
    foreach ($params['noise'] as $percentage) {
        $count = intdiv(count($train) * $percentage, 100);
        $generator = new Minstd($params['noiseSeed']);
        $permutation = range(0, count($train) - 1);
        for ($i = 0; $i < $count; $i++) {
            $other = $i + $generator->next() % (count($train) - $i);
            [$permutation[$i], $permutation[$other]] = [$permutation[$other], $permutation[$i]];
        }
        $flipped = array_fill(0, count($train), false);
        foreach (array_slice($permutation, 0, $count) as $i) $flipped[$i] = true;
        $noisy = [];
        foreach ($train as $i => $row) {
            if ($flipped[$i]) $row['label'] = -$row['label'];
            $noisy[] = $row;
        }
        $lines[] = fields('noise', $percentage, 'flipped', $count);
        foreach ($params['variants'] as $variant) {
            $model = train_variant($variant, $noisy, $params);
            $stats = experiment_stats($model, $noisy, $test);
            $weights = $model['rounds'][count($model['rounds']) - 1]['weights'];
            $flippedWeight = 0.0;
            foreach ($train as $i => $row) if ($flipped[$i]) $flippedWeight += $weights[$i];
            $lines[] = fields($variant, experiment_fields($model, $stats, count($train), count($test)),
                'test_min', $stats['minimum'] . '/' . count($test), 'at', $stats['at'], 'flipped_weight', fixed($flippedWeight));
        }
    }
    return $lines;
}

function main()
{
    $data = read_dataset();
    $cv = cross_validation($data['train'], $data['params']);
    $models = analyze_models($data, $cv);
    $multi = multiclass_analysis($data);
    $outputs = [
        ['ensemble.txt', ensemble_lines($data, $models, $cv)],
        ['error_curve.csv', error_curve_lines($data, $models, $multi)],
        ['predictions.csv', prediction_lines($data, $models)],
        ['roc.csv', roc_lines($data, $models)],
        ['margins.txt', margin_lines($data, $models)],
        ['shapes.txt', shape_lines($data, $models)],
        ['samme.txt', samme_lines($data, $multi)],
        ['summary.txt', summary_lines($data, $models, $cv)],
        ['experiments.txt', experiment_lines($data, $models, $cv)]
    ];
    foreach ($outputs as [$name, $lines]) write_lines($name, $lines);
}

main();
