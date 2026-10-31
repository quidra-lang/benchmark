<?php

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/linalg.php';
require_once __DIR__ . '/gaussian_models.php';
require_once __DIR__ . '/evaluation.php';
require_once __DIR__ . '/plot.php';

const MODELS = ['NB', 'LDA', 'QDA'];

function fields(...$values)
{
    return implode(' ', $values);
}

function real_values($values)
{
    return implode(' ', array_map('plot_real', $values));
}

function ratio($numerator, $denominator)
{
    return plot_fraction(ev_fraction($numerator, $denominator));
}

function predicted_classes($results)
{
    return array_column($results, 'predicted');
}

function sections($parts)
{
    $lines = [];
    foreach ($parts as $index => $part) {
        if ($index > 0) $lines[] = '';
        foreach ($part as $line) $lines[] = $line;
    }
    return $lines;
}

function correct_count($rows, $predicted)
{
    $count = 0;
    foreach ($rows as $i => $row) if ($row['class'] === $predicted[$i]) $count++;
    return $count;
}

function fit($data, $type, $features = null, $rows = null, $changes = [])
{
    return gm_train($rows ?? $data['train'], $features ?? $data['all'], $type,
        array_replace($data['settings'], $changes), count($data['classes']));
}

function classify_rows($model, $rows, $costs = null)
{
    $results = [];
    foreach ($rows as $row) $results[] = gm_predict_row($model, $row, $costs);
    return $results;
}

function cross_validation(&$data, $type, $features = null, $changes = [])
{
    $features = $features ?? $data['all'];
    $settings = array_replace($data['settings'], $changes);
    $key = json_encode([$type, $features, $settings['prior'], $settings['epsilon'], $settings['gamma']]);
    if (isset($data['cv'][$key])) return $data['cv'][$key];
    $predicted = array_fill(0, count($data['train']), 0);
    $folds = array_fill(0, $settings['folds'], 0);
    for ($fold = 0; $fold < $settings['folds']; $fold++) {
        $rows = [];
        foreach ($data['train'] as $row) if ($row['id'] % $settings['folds'] !== $fold) $rows[] = $row;
        $model = fit($data, $type, $features, $rows, $changes);
        foreach ($data['train'] as $i => $row) {
            if ($row['id'] % $settings['folds'] !== $fold) continue;
            $predicted[$i] = gm_predict_row($model, $row)['predicted'];
            if ($predicted[$i] === $row['class']) $folds[$fold]++;
        }
    }
    $result = ['predicted' => $predicted, 'folds' => $folds, 'correct' => correct_count($data['train'], $predicted)];
    $data['cv'][$key] = $result;
    return $result;
}

function model_report($data, $models)
{
    [$nb, $lda, $qda] = $models;
    $names = $data['classes'];
    $settings = $data['settings'];
    $parts = [];
    $description = ['features ' . implode(' ', $data['features']), 'classes ' . implode(' ', $names), 'prior_mode ' . $settings['prior']];
    foreach ($nb['classes'] as $i => $group) {
        $description[] = fields('class', $names[$i], 'letter', strtoupper($names[$i][0]), 'count', $group['count'],
            'prior', plot_real($group['prior']), 'mean', real_values($group['mean']));
    }
    $parts[] = $description;
    $naive = ['model NB', fields('smoothing epsilon', plot_real($settings['epsilon']), 'max_variance', plot_real($nb['maximumVariance']), 'added', plot_real($nb['added']))];
    foreach ($nb['classes'] as $i => $group) {
        $diagonal = [];
        foreach ($group['covariance'] as $j => $row) $diagonal[] = $row[$j];
        $naive[] = fields('class', $names[$i], 'variance', real_values($diagonal), 'log_det', plot_real($group['logDeterminant']));
    }
    $parts[] = $naive;
    $linear = ['model LDA', 'log_det ' . plot_real($lda['classes'][0]['logDeterminant'])];
    foreach ($lda['classes'][0]['covariance'] as $row) $linear[] = '  ' . real_values($row);
    foreach ($lda['classes'] as $i => $group) {
        $coefficient = la_backward($group['lower'], la_forward($group['lower'], $group['mean']));
        $product = 0.0;
        foreach ($group['mean'] as $j => $value) $product += $value * $coefficient[$j];
        $linear[] = fields('class', $names[$i], 'intercept', plot_real(log($group['prior']) - $product / 2), 'coef', real_values($coefficient));
    }
    $parts[] = $linear;
    $quadratic = ['model QDA gamma ' . plot_real($settings['gamma'])];
    foreach ($qda['classes'] as $i => $group) {
        $eigenvalues = la_jacobi($group['covariance'])['values'];
        rsort($eigenvalues, SORT_NUMERIC);
        $quadratic[] = fields('class', $names[$i], 'log_det', plot_real($group['logDeterminant']), 'eigenvalues', real_values($eigenvalues),
            'condition', plot_real($eigenvalues[0] / $eigenvalues[count($eigenvalues) - 1]));
        foreach ($group['covariance'] as $row) $quadratic[] = '  ' . real_values($row);
    }
    $parts[] = $quadratic;
    $separation = ['separation'];
    for ($a = 0; $a < count($names); $a++) {
        for ($b = $a + 1; $b < count($names); $b++) {
            $first = $qda['classes'][$a];
            $second = $qda['classes'][$b];
            $difference = [];
            $average = la_matrix(count($data['features']));
            foreach ($first['mean'] as $i => $value) {
                $difference[] = $value - $second['mean'][$i];
                foreach ($first['covariance'][$i] as $j => $entry) $average[$i][$j] = ($entry + $second['covariance'][$i][$j]) / 2;
            }
            $lower = la_cholesky($average);
            $mahalanobis = sqrt(la_quadratic($lda['classes'][0]['lower'], $difference));
            $bhattacharyya = la_quadratic($lower, $difference) / 8
                + (la_log_determinant($lower) - ($first['logDeterminant'] + $second['logDeterminant']) / 2) / 2;
            $separation[] = fields($names[$a], $names[$b], 'mahalanobis', plot_real($mahalanobis), 'bhattacharyya', plot_real($bhattacharyya));
        }
    }
    $parts[] = $separation;
    $outliers = [];
    foreach ($data['train'] as $i => $row) {
        $q = gm_predict_row($qda, $row)['distances'][$row['class']];
        if ($q > $settings['outlier']) $outliers[] = ['row' => $row, 'index' => $i, 'q' => $q];
    }
    usort($outliers, fn($a, $b) => ($b['q'] <=> $a['q']) ?: ($a['index'] <=> $b['index']));
    $lines = ['outliers threshold ' . plot_real($settings['outlier'])];
    foreach ($outliers as $item) $lines[] = fields($item['row']['id'], $item['row']['label'], 'q', plot_real($item['q']));
    $lines[] = 'count ' . count($outliers);
    $parts[] = $lines;
    return sections($parts);
}

function prediction_report($data, $results)
{
    $lines = [implode(',', array_merge(['id', 'model', 'actual', 'predicted', 'decision'], $data['classes']))];
    foreach ($data['test'] as $i => $row) {
        foreach (MODELS as $j => $name) {
            $result = $results[$j][$i];
            $lines[] = implode(',', array_merge([$row['id'], $name, $row['label'], $data['classes'][$result['predicted']],
                $data['classes'][$result['decision']]], array_map('plot_real', $result['posterior'])));
        }
    }
    return $lines;
}

function confusion_lines($data, $metrics)
{
    $lines = [];
    foreach ($metrics['table'] as $i => $row) $lines[] = 'confusion ' . $data['classes'][$i] . ' ' . implode(' ', $row);
    return $lines;
}

function evaluate_model($data, $type, $results)
{
    $predicted = predicted_classes($results);
    $metrics = ev_confusion($data['test'], $predicted, count($data['classes']));
    $lines = array_merge(['model ' . $type], confusion_lines($data, $metrics),
        ['accuracy ' . plot_fraction($metrics['accuracy']), 'balanced_accuracy ' . plot_fraction($metrics['balanced']), 'kappa ' . plot_fraction($metrics['kappa'])]);
    foreach ($metrics['classes'] as $i => $group) {
        $lines[] = fields('class', $data['classes'][$i], 'support', $group['support'], 'recall', plot_fraction($group['recall']),
            'precision', plot_fraction($group['precision']), 'f1', plot_fraction($group['f1']));
    }
    $logProbability = 0.0;
    foreach ($data['test'] as $i => $row) $logProbability += $results[$i]['logPosterior'][$row['class']];
    $lines[] = 'macro_f1 ' . plot_real($metrics['macroF1']);
    $lines[] = 'log_loss ' . plot_real(-$logProbability / count($data['test']));
    $lines[] = 'errors ' . (count($data['test']) - $metrics['correct']);
    foreach ($data['test'] as $i => $row) {
        if ($row['class'] !== $predicted[$i]) {
            $lines[] = fields('error', $row['id'], 'actual', $row['label'], 'predicted', $data['classes'][$predicted[$i]], 'confidence', plot_real($results[$i]['confidence']));
        }
    }
    $edges = array_merge([0.0], $data['settings']['calibration'], [1.0]);
    $calibrationError = 0.0;
    for ($bin = 0; $bin + 1 < count($edges); $bin++) {
        $count = 0;
        $correct = 0;
        $confidence = 0.0;
        foreach ($data['test'] as $i => $row) {
            $value = $results[$i]['confidence'];
            if ($value < $edges[$bin] || ($bin + 2 === count($edges) ? $value > $edges[$bin + 1] : $value >= $edges[$bin + 1])) continue;
            $count++;
            if ($row['class'] === $predicted[$i]) $correct++;
            $confidence += $value;
        }
        $lines[] = fields('bin', plot_real($edges[$bin]), plot_real($edges[$bin + 1]), 'count', $count, 'confidence',
            $count === 0 ? '-' : plot_real($confidence / $count), 'accuracy', ratio($correct, $count));
        $calibrationError += abs($correct - $confidence);
    }
    $lines[] = 'ece ' . plot_real($calibrationError / count($data['test']));
    foreach ($data['settings']['reject'] as $threshold) {
        $count = 0;
        $correct = 0;
        foreach ($data['test'] as $i => $row) {
            if ($results[$i]['confidence'] < $threshold) continue;
            $count++;
            if ($row['class'] === $predicted[$i]) $correct++;
        }
        $lines[] = fields('reject', plot_real($threshold), 'accepted', $count, 'coverage', ratio($count, count($data['test'])), 'accuracy', ratio($correct, $count));
    }
    return $lines;
}

function comparison_lines($rows, $names, $predicted)
{
    $lines = [];
    for ($a = 0; $a < count($names); $a++) {
        for ($b = $a + 1; $b < count($names); $b++) {
            $result = ev_mcnemar($rows, $predicted[$a], $predicted[$b]);
            $lines[] = fields($names[$a], $names[$b], 'b01', $result['b01'], 'b10', $result['b10'],
                'chi2', plot_real($result['chi2']), 'significant', $result['significant'] ? 'yes' : 'no');
        }
    }
    return $lines;
}

function bootstrap_report($data, $predicted)
{
    $settings = $data['settings'];
    $random = new RandomGenerator($settings['seed']);
    $samples = [[], [], []];
    $m = count($data['test']);
    for ($sample = 0; $sample < $settings['resamples']; $sample++) {
        $counts = [0, 0, 0];
        for ($draw = 0; $draw < $m; $draw++) {
            $index = $random->next() % $m;
            for ($j = 0; $j < count(MODELS); $j++) if ($predicted[$j][$index] === $data['test'][$index]['class']) $counts[$j]++;
        }
        foreach ($counts as $j => $count) $samples[$j][] = $count;
    }
    $lines = [fields('bootstrap resamples', $settings['resamples'], 'seed', $settings['seed'])];
    $offset = intdiv($settings['resamples'], 40);
    foreach ($samples as $j => $sample) {
        $ordered = $sample;
        sort($ordered, SORT_NUMERIC);
        $total = 0;
        foreach ($sample as $count) $total += $count;
        $lines[] = fields(MODELS[$j], 'mean', plot_real($total / $settings['resamples'] / $m), 'interval',
            ratio($ordered[$offset], $m), ratio($ordered[count($ordered) - 1 - $offset], $m));
    }
    for ($a = 0; $a < count(MODELS); $a++) {
        for ($b = $a + 1; $b < count(MODELS); $b++) {
            $wins = 0;
            $ties = 0;
            $losses = 0;
            for ($i = 0; $i < $settings['resamples']; $i++) {
                if ($samples[$a][$i] > $samples[$b][$i]) $wins++;
                elseif ($samples[$a][$i] === $samples[$b][$i]) $ties++;
                else $losses++;
            }
            $lines[] = fields(MODELS[$a], MODELS[$b], 'wins', $wins, 'ties', $ties, 'losses', $losses);
        }
    }
    return $lines;
}

function subset_report(&$data)
{
    $sizes = array_fill(0, $data['settings']['folds'], 0);
    foreach ($data['train'] as $row) $sizes[$row['id'] % $data['settings']['folds']]++;
    $lines = ['cross_validation folds ' . $data['settings']['folds'], 'fold_sizes ' . implode(' ', $sizes)];
    $best = null;
    foreach ($data['settings']['subsets'] as $subset) {
        $names = [];
        foreach ($subset['features'] as $feature) $names[] = $data['features'][$feature];
        $lines[] = fields('subset', $subset['name'], 'features', implode(' ', $names));
        foreach (MODELS as $type) {
            $result = cross_validation($data, $type, $subset['features']);
            $lines[] = '  ' . fields($type, 'fold_correct', implode(' ', $result['folds']), 'correct', $result['correct'],
                'accuracy', ratio($result['correct'], count($data['train'])));
            if ($best === null || $result['correct'] > $best['correct'] ||
                ($result['correct'] === $best['correct'] && count($subset['features']) < count($best['subset']['features']))) {
                $best = ['subset' => $subset, 'type' => $type, 'correct' => $result['correct']];
            }
        }
    }
    $model = fit($data, $best['type'], $best['subset']['features']);
    $count = correct_count($data['test'], predicted_classes(classify_rows($model, $data['test'])));
    $lines[] = fields('best subset', $best['subset']['name'], 'model', $best['type'], 'correct', $best['correct'],
        'accuracy', ratio($best['correct'], count($data['train'])));
    $lines[] = fields('refit_test correct', $count, 'accuracy', ratio($count, count($data['test'])));
    return $lines;
}

function leave_one_out_report($data)
{
    $lines = ['leave_one_out'];
    foreach (MODELS as $type) {
        $correct = 0;
        foreach ($data['train'] as $i => $row) {
            $remaining = [];
            foreach ($data['train'] as $j => $other) if ($j !== $i) $remaining[] = $other;
            if (gm_predict_row(fit($data, $type, $data['all'], $remaining), $row)['predicted'] === $row['class']) $correct++;
        }
        $lines[] = fields($type, 'correct', $correct, 'accuracy', ratio($correct, count($data['train'])));
    }
    return $lines;
}

function forward_selection_report(&$data, $type)
{
    $selected = [];
    $lines = ['forward_selection model ' . $type];
    $best = null;
    while (count($selected) < count($data['features'])) {
        $candidate = null;
        foreach ($data['all'] as $feature) {
            if (in_array($feature, $selected, true)) continue;
            $features = $selected;
            $features[] = $feature;
            $result = cross_validation($data, $type, $features);
            if ($candidate === null || $result['correct'] > $candidate['correct']) $candidate = ['feature' => $feature, 'correct' => $result['correct']];
        }
        $selected[] = $candidate['feature'];
        $lines[] = fields('step', count($selected), 'add', $data['features'][$candidate['feature']], 'correct', $candidate['correct'],
            'accuracy', ratio($candidate['correct'], count($data['train'])));
        if ($best === null || $candidate['correct'] > $best['correct']) $best = ['correct' => $candidate['correct'], 'features' => $selected];
    }
    $names = [];
    foreach ($best['features'] as $feature) $names[] = $data['features'][$feature];
    $lines[] = fields('best_step', count($best['features']), 'features', implode(' ', $names));
    return $lines;
}

function tuning_report(&$data, $type, $parameter, $grid, $heading)
{
    $lines = [$heading];
    $best = null;
    foreach ($grid as $value) {
        $result = cross_validation($data, $type, $data['all'], [$parameter => $value]);
        $lines[] = fields('value', plot_real($value), 'correct', $result['correct'], 'accuracy', ratio($result['correct'], count($data['train'])));
        if ($best === null || $result['correct'] >= $best['correct']) $best = ['value' => $value, 'correct' => $result['correct']];
    }
    $model = fit($data, $type, $data['all'], $data['train'], [$parameter => $best['value']]);
    $count = correct_count($data['test'], predicted_classes(classify_rows($model, $data['test'])));
    $lines[] = fields('best', plot_real($best['value']), 'test correct', $count, 'accuracy', ratio($count, count($data['test'])));
    return $lines;
}

function evaluation_report(&$data, $results)
{
    $parts = [['test rows ' . count($data['test'])]];
    foreach (MODELS as $i => $type) $parts[] = evaluate_model($data, $type, $results[$i]);
    $predicted = array_map('predicted_classes', $results);
    $ensemble = [];
    foreach ($data['test'] as $i => $row) {
        $probabilities = [];
        foreach ($data['classes'] as $k => $name) {
            $total = 0.0;
            for ($model = 0; $model < count(MODELS); $model++) $total += $results[$model][$i]['posterior'][$k];
            $probabilities[] = $total / 3;
        }
        $best = 0;
        for ($k = 1; $k < count($probabilities); $k++) if ($probabilities[$k] > $probabilities[$best]) $best = $k;
        $ensemble[] = $best;
    }
    $metrics = ev_confusion($data['test'], $ensemble, count($data['classes']));
    $parts[] = ['ensemble soft_vote', fields('accuracy', plot_fraction($metrics['accuracy']), 'balanced_accuracy',
        plot_fraction($metrics['balanced']), 'kappa', plot_fraction($metrics['kappa']))];
    $parts[] = array_merge(['mcnemar test'], comparison_lines($data['test'], array_merge(MODELS, ['ENSEMBLE']), array_merge($predicted, [$ensemble])));
    $costs = ['costs'];
    foreach ($results as $j => $model) {
        $predictedCost = 0.0;
        $decidedCost = 0.0;
        $changed = 0;
        $correct = 0;
        foreach ($data['test'] as $i => $row) {
            $result = $model[$i];
            $predictedCost += $data['costs'][$row['class']][$result['predicted']];
            $decidedCost += $data['costs'][$row['class']][$result['decision']];
            if ($result['predicted'] !== $result['decision']) $changed++;
            if ($result['decision'] === $row['class']) $correct++;
        }
        $costs[] = fields(MODELS[$j], 'argmax_total', plot_real($predictedCost), 'decision_total', plot_real($decidedCost),
            'changed', $changed, 'decision_accuracy', ratio($correct, count($data['test'])));
    }
    $parts[] = $costs;
    $novel = [];
    foreach ($results[2] as $i => $result) {
        $nearest = 0;
        for ($k = 1; $k < count($data['classes']); $k++) if ($result['distances'][$k] < $result['distances'][$nearest]) $nearest = $k;
        if ($result['distances'][$nearest] > $data['settings']['outlier']) $novel[] = ['index' => $i, 'nearest' => $nearest, 'q' => $result['distances'][$nearest]];
    }
    usort($novel, fn($a, $b) => ($b['q'] <=> $a['q']) ?: ($a['index'] <=> $b['index']));
    $lines = ['novelty threshold ' . plot_real($data['settings']['outlier'])];
    foreach ($novel as $item) $lines[] = fields($data['test'][$item['index']]['id'], 'nearest', $data['classes'][$item['nearest']], 'q', plot_real($item['q']));
    $lines[] = 'count ' . count($novel);
    $parts[] = $lines;
    $parts[] = bootstrap_report($data, $predicted);
    $prior = $data['settings']['prior'] === 'empirical' ? 'uniform' : 'empirical';
    $sensitivity = ['prior_sensitivity alternative ' . $prior];
    foreach (MODELS as $j => $type) {
        $alternative = predicted_classes(classify_rows(fit($data, $type, $data['all'], $data['train'], ['prior' => $prior]), $data['test']));
        $metrics = ev_confusion($data['test'], $alternative, count($data['classes']));
        $changed = 0;
        foreach ($alternative as $i => $choice) if ($choice !== $predicted[$j][$i]) $changed++;
        $sensitivity[] = fields($type, 'accuracy', plot_fraction($metrics['accuracy']), 'balanced_accuracy', plot_fraction($metrics['balanced']), 'changed', $changed);
    }
    $parts[] = $sensitivity;
    $learning = ['learning_curve'];
    foreach ($data['settings']['curve'] as $size) {
        $taken = array_fill(0, count($data['classes']), 0);
        $rows = [];
        foreach ($data['train'] as $row) {
            $taken[$row['class']]++;
            if ($taken[$row['class']] <= $size) $rows[] = $row;
        }
        $line = ['size', $size, 'rows', count($rows)];
        foreach (MODELS as $type) {
            $count = correct_count($data['test'], predicted_classes(classify_rows(fit($data, $type, $data['all'], $rows), $data['test'])));
            $line[] = $type;
            $line[] = ratio($count, count($data['test']));
        }
        $learning[] = fields(...$line);
    }
    $parts[] = $learning;
    $parts[] = subset_report($data);
    $validation = [];
    foreach (MODELS as $type) $validation[] = cross_validation($data, $type);
    $parts[] = array_merge(['mcnemar cross_validation'], comparison_lines($data['train'], MODELS, array_column($validation, 'predicted')));
    foreach ($validation as $i => $result) {
        $metrics = ev_confusion($data['train'], $result['predicted'], count($data['classes']));
        $parts[] = array_merge(['cv_confusion model ' . MODELS[$i]], confusion_lines($data, $metrics),
            [fields('balanced_accuracy', plot_fraction($metrics['balanced']), 'kappa', plot_fraction($metrics['kappa']))]);
    }
    $parts[] = leave_one_out_report($data);
    foreach (MODELS as $type) $parts[] = forward_selection_report($data, $type);
    $parts[] = tuning_report($data, 'NB', 'epsilon', $data['settings']['smoothingGrid'], 'nb_smoothing_path');
    $parts[] = tuning_report($data, 'QDA', 'gamma', $data['settings']['gammaGrid'], 'qda_gamma_path');
    return sections($parts);
}

function empty_grid($width, $height)
{
    return array_fill(0, $height, array_fill(0, $width, ' '));
}

function place_point(&$grid, $column, $row, $letter)
{
    $previous = $grid[$row][$column];
    $grid[$row][$column] = $previous === ' ' || $previous === $letter ? $letter : '*';
}

function boundary_report(&$data)
{
    $parts = [];
    $width = $data['settings']['width'];
    $height = $data['settings']['height'];
    foreach ($data['settings']['pairs'] as $features) {
        [$fx, $fy] = $features;
        $xs = [];
        $ys = [];
        foreach ($data['train'] as $row) {
            $xs[] = $row['values'][$fx];
            $ys[] = $row['values'][$fy];
        }
        $xmin = min($xs);
        $xmax = max($xs);
        $ymin = min($ys);
        $ymax = max($ys);
        $dx = ($xmax - $xmin) / ($width - 1);
        $dy = ($ymax - $ymin) / ($height - 1);
        $lines = [fields('pair', $data['features'][$fx], $data['features'][$fy]),
            fields('x', $data['features'][$fx], plot_real($xmin), plot_real($xmax), 'y', $data['features'][$fy], plot_real($ymin), plot_real($ymax), 'grid', $width . 'x' . $height)];
        $maps = [];
        $uncertainty = empty_grid($width, $height);
        foreach (MODELS as $type) {
            $model = fit($data, $type, $features);
            $correct = correct_count($data['train'], predicted_classes(classify_rows($model, $data['train'])));
            $validation = cross_validation($data, $type, $features);
            $lines[] = fields('model', $type, 'train_accuracy', ratio($correct, count($data['train'])),
                'cv_accuracy', ratio($validation['correct'], count($data['train'])));
            $region = empty_grid($width, $height);
            $counts = array_fill(0, count($data['classes']), 0);
            $choices = [];
            for ($r = 0; $r < $height; $r++) {
                $chosen = [];
                for ($c = 0; $c < $width; $c++) {
                    $result = gm_predict($model, [$xmin + $c * $dx, $ymax - $r * $dy]);
                    $region[$r][$c] = strtoupper($data['classes'][$result['predicted']][0]);
                    $counts[$result['predicted']]++;
                    $chosen[] = $result['predicted'];
                    if ($type === 'QDA') {
                        $u = (1 - $result['confidence']) / (1 - 1 / count($data['classes']));
                        $level = min(9, (int) floor(10 * $u));
                        $levels = ' .:-=+*#%@';
                        $uncertainty[$r][$c] = $levels[$level];
                    }
                }
                $choices[] = $chosen;
            }
            $maps[] = $choices;
            foreach (plot_frame($region) as $line) $lines[] = $line;
            $cells = ['cells'];
            foreach ($data['classes'] as $k => $name) {
                $cells[] = strtoupper($name[0]);
                $cells[] = $counts[$k];
            }
            $lines[] = fields(...$cells);
        }
        $agreement = empty_grid($width, $height);
        $disagreements = 0;
        for ($r = 0; $r < $height; $r++) {
            for ($c = 0; $c < $width; $c++) {
                $distinct = count(array_unique([$maps[0][$r][$c], $maps[1][$r][$c], $maps[2][$r][$c]]));
                $agreement[$r][$c] = $distinct === 1 ? '.' : (string) $distinct;
                if ($distinct !== 1) $disagreements++;
            }
        }
        $points = empty_grid($width, $height);
        foreach ($data['train'] as $row) {
            $column = plot_cell($row['values'][$fx], $xmin, $xmax, $width);
            $line = $height - 1 - plot_cell($row['values'][$fy], $ymin, $ymax, $height);
            place_point($points, $column, $line, $data['classes'][$row['class']][0]);
        }
        $lines[] = 'agreement';
        foreach (plot_frame($agreement) as $line) $lines[] = $line;
        $lines[] = 'disagreement_cells ' . $disagreements;
        $lines[] = 'uncertainty QDA';
        foreach (plot_frame($uncertainty) as $line) $lines[] = $line;
        $lines[] = 'points';
        foreach (plot_frame($points) as $line) $lines[] = $line;
        $parts[] = $lines;
    }
    return sections($parts);
}

function fisher_directions($within, $between)
{
    $dimension = count($within);
    $lower = la_cholesky($within);
    $first = la_matrix($dimension);
    for ($column = 0; $column < $dimension; $column++) {
        $vector = [];
        for ($row = 0; $row < $dimension; $row++) $vector[] = $between[$row][$column];
        $result = la_forward($lower, $vector);
        for ($row = 0; $row < $dimension; $row++) $first[$row][$column] = $result[$row];
    }
    $second = la_matrix($dimension);
    for ($column = 0; $column < $dimension; $column++) {
        $result = la_forward($lower, $first[$column]);
        for ($row = 0; $row < $dimension; $row++) $second[$row][$column] = $result[$row];
    }
    $symmetric = la_matrix($dimension);
    for ($a = 0; $a < $dimension; $a++) {
        for ($b = 0; $b < $dimension; $b++) $symmetric[$a][$b] = ($second[$a][$b] + $second[$b][$a]) / 2;
    }
    $eigen = la_jacobi($symmetric);
    $order = range(0, $dimension - 1);
    usort($order, fn($a, $b) => ($eigen['values'][$b] <=> $eigen['values'][$a]) ?: ($a <=> $b));
    $total = 0.0;
    foreach ($eigen['values'] as $value) $total += $value;
    $directions = [];
    foreach (array_slice($order, 0, 2) as $index) {
        $vector = [];
        foreach ($eigen['vectors'] as $row) $vector[] = $row[$index];
        $vector = la_backward($lower, $vector);
        $norm = 0.0;
        foreach ($vector as $value) $norm += $value * $value;
        $norm = sqrt($norm);
        $direction = [];
        foreach ($vector as $value) $direction[] = $value / $norm;
        $largest = 0;
        for ($j = 1; $j < $dimension; $j++) if (abs($direction[$j]) > abs($direction[$largest])) $largest = $j;
        if ($direction[$largest] < 0) foreach ($direction as &$value) $value = -$value;
        unset($value);
        $directions[] = $direction;
    }
    $eigenvalues = [];
    $ratios = [];
    foreach ($order as $index) {
        $eigenvalues[] = $eigen['values'][$index];
        $ratios[] = $eigen['values'][$index] / $total;
    }
    return ['directions' => $directions, 'sweeps' => $eigen['sweeps'], 'eigenvalues' => $eigenvalues, 'ratios' => $ratios];
}

function project_vector($vector, $directions, $center)
{
    $result = [];
    foreach ($directions as $direction) {
        $value = 0.0;
        foreach ($vector as $j => $component) $value += $direction[$j] * ($component - $center[$j]);
        $result[] = $value;
    }
    return $result;
}

function nearest_count($rows, $projections, $centroids, $dimensions)
{
    $correct = 0;
    foreach ($rows as $i => $row) {
        $nearest = 0;
        $minimum = null;
        foreach ($centroids as $k => $centroid) {
            $first = $projections[$i][0] - $centroid[0];
            $distance = $first * $first;
            if ($dimensions === 2) {
                $second = $projections[$i][1] - $centroid[1];
                $distance += $second * $second;
            }
            if ($minimum === null || $distance < $minimum) {
                $minimum = $distance;
                $nearest = $k;
            }
        }
        if ($nearest === $row['class']) $correct++;
    }
    return $correct;
}

function projection_report($data, $lda)
{
    $dimension = count($data['features']);
    $count = count($data['classes']);
    $center = $lda['data']['center'];
    $classes = $lda['data']['classes'];
    $within = la_matrix($dimension);
    $between = la_matrix($dimension);
    for ($a = 0; $a < $dimension; $a++) {
        for ($b = 0; $b < $dimension; $b++) {
            foreach ($classes as $group) {
                $within[$a][$b] += $group['scatter'][$a][$b];
                $between[$a][$b] += $group['count'] * ($group['mean'][$a] - $center[$a]) * ($group['mean'][$b] - $center[$b]);
            }
        }
    }
    $fvalues = [];
    foreach ($data['all'] as $j) $fvalues[] = ($between[$j][$j] / ($count - 1)) / ($within[$j][$j] / (count($data['train']) - $count));
    $order = $data['all'];
    usort($order, fn($a, $b) => ($fvalues[$b] <=> $fvalues[$a]) ?: ($a <=> $b));
    $univariate = ['univariate'];
    foreach ($order as $rank => $j) {
        $univariate[] = fields('rank', $rank + 1, $data['features'][$j], 'f', plot_real($fvalues[$j]),
            'between', plot_real($between[$j][$j]), 'within', plot_real($within[$j][$j]));
    }
    $fisher = fisher_directions($within, $between);
    $lines = ['fisher features ' . implode(' ', $data['features']), 'center ' . real_values($center), 'sweeps ' . $fisher['sweeps'],
        'eigenvalues ' . real_values($fisher['eigenvalues']), 'ratios ' . real_values($fisher['ratios'])];
    foreach ($fisher['directions'] as $i => $direction) {
        $standardized = [];
        foreach ($direction as $j => $value) $standardized[] = $value * sqrt($lda['classes'][0]['covariance'][$j][$j]);
        $lines[] = fields('direction', $i + 1, real_values($direction));
        $lines[] = fields('standardized', $i + 1, real_values($standardized));
    }
    $centroids = [];
    foreach ($classes as $group) $centroids[] = project_vector($group['mean'], $fisher['directions'], $center);
    $training = [];
    foreach ($data['train'] as $row) $training[] = project_vector($row['values'], $fisher['directions'], $center);
    $testing = [];
    foreach ($data['test'] as $row) $testing[] = project_vector($row['values'], $fisher['directions'], $center);
    foreach ($classes as $k => $group) {
        $spread = [];
        for ($direction = 0; $direction < 2; $direction++) {
            $total = 0.0;
            foreach ($data['train'] as $i => $row) {
                if ($row['class'] !== $k) continue;
                $difference = $training[$i][$direction] - $centroids[$k][$direction];
                $total += $difference * $difference;
            }
            $spread[] = sqrt($total / $group['count']);
        }
        $lines[] = fields('centroid', $data['classes'][$k], real_values($centroids[$k]), 'spread', real_values($spread));
    }
    foreach ([1, 2] as $dimensions) {
        $lines[] = fields('nearest_centroid dims', $dimensions,
            'train', ratio(nearest_count($data['train'], $training, $centroids, $dimensions), count($data['train'])),
            'test', ratio(nearest_count($data['test'], $testing, $centroids, $dimensions), count($data['test'])));
    }
    $x = array_column($training, 0);
    $y = array_column($training, 1);
    $low1 = min($x);
    $high1 = max($x);
    $low2 = min($y);
    $high2 = max($y);
    $width = $data['settings']['plotWidth'];
    $height = $data['settings']['plotHeight'];
    $grid = empty_grid($width, $height);
    foreach ($training as $i => $point) {
        $column = plot_cell($point[0], $low1, $high1, $width);
        $row = $height - 1 - plot_cell($point[1], $low2, $high2, $height);
        place_point($grid, $column, $row, $data['classes'][$data['train'][$i]['class']][0]);
    }
    foreach ($centroids as $k => $point) {
        $column = plot_cell($point[0], $low1, $high1, $width);
        $row = $height - 1 - plot_cell($point[1], $low2, $high2, $height);
        $grid[$row][$column] = strtoupper($data['classes'][$k][0]);
    }
    $plot = [fields('plot x', plot_real($low1), plot_real($high1), 'y', plot_real($low2), plot_real($high2), 'size', $width . 'x' . $height)];
    foreach (plot_frame($grid) as $line) $plot[] = $line;
    return sections([$univariate, $lines, $plot]);
}

function main()
{
    $data = read_dataset();
    $data['all'] = range(0, count($data['features']) - 1);
    $data['cv'] = [];
    $models = [];
    foreach (MODELS as $type) $models[] = fit($data, $type);
    $results = [];
    foreach ($models as $model) $results[] = classify_rows($model, $data['test'], $data['costs']);
    $modelLines = model_report($data, $models);
    $predictionLines = prediction_report($data, $results);
    $evaluationLines = evaluation_report($data, $results);
    $boundaryLines = boundary_report($data);
    $projectionLines = projection_report($data, $models[1]);
    if (!is_dir('output')) mkdir('output', 0777, true);
    plot_write_lines('models.txt', $modelLines);
    plot_write_lines('predictions.csv', $predictionLines);
    plot_write_lines('evaluation.txt', $evaluationLines);
    plot_write_lines('boundaries.txt', $boundaryLines);
    plot_write_lines('projection.txt', $projectionLines);
}

main();
