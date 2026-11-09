<?php

require_once __DIR__ . '/dataframe.php';
require_once __DIR__ . '/formula.php';
require_once __DIR__ . '/qr_solver.php';
require_once __DIR__ . '/inference.php';
require_once __DIR__ . '/diagnostics.php';

function modelStatistics($fitting, $parameters, $inference = true) {
    $n = $fitting['n'];
    $rank = $fitting['rank'];
    $weights = $fitting['weights'];
    $response = $fitting['response'];
    $rss = $fitting['rss'];
    $df = $n - $rank;
    $sigma = sqrt($rss / $df);
    $weightSum = $weightedY = $logWeights = 0.0;
    for ($i = 0; $i < $n; $i++) {
        $weightSum += $weights[$i];
        $weightedY += $weights[$i] * $response[$i];
        $logWeights += log($weights[$i]);
    }
    $mean = $weightedY / $weightSum;
    $tss = $press = 0.0;
    for ($i = 0; $i < $n; $i++) {
        $tss += $weights[$i] * ($response[$i] - $mean) * ($response[$i] - $mean);
        $part = $fitting['weightedResiduals'][$i] / (1 - $fitting['leverage'][$i]);
        $press += $part * $part;
    }
    $r2 = 1 - $rss / $tss;
    $adjusted = 1 - (1 - $r2) * ($n - 1) / $df;
    $f = $rank > 1 ? (($tss - $rss) / ($rank - 1)) / ($rss / $df) : null;
    $loglik = 0.5 * ($logWeights - $n * (log(2 * 3.141592653589793) + 1 - log($n) + log($rss)));
    $aic = -2 * $loglik + 2 * ($rank + 1);
    $bic = -2 * $loglik + log($n) * ($rank + 1);
    $predicted = 1 - $press / $tss;
    $ordered = $fitting['weightedResiduals'];
    sort($ordered, SORT_NUMERIC);
    $quantiles = [];
    foreach ([0, 0.25, 0.5, 0.75, 1] as $proportion) {
        $position = ($n - 1) * $proportion;
        $lower = (int)floor($position);
        $quantiles[] = $lower + 1 < $n ? $ordered[$lower] + ($position - $lower) * ($ordered[$lower + 1] - $ordered[$lower]) : $ordered[$lower];
    }
    $fp = $inference && $rank > 1 ? fP($f, $rank - 1, $df) : null;
    $critical = $inference ? tQuantile($parameters['CONFIDENCE'], $df) : null;
    return compact('df', 'sigma', 'weightSum', 'mean', 'tss', 'r2', 'adjusted', 'f', 'fp', 'loglik', 'aic', 'bic', 'press', 'predicted', 'quantiles', 'critical');
}

function fitTerms($model, $terms, $parameters, $inference = false) {
    $built = design($model, $model['rows'], $model['levels'], $terms);
    $fitting = fit($built['matrix'], $built['response'], $built['weights'], $parameters['RANK_TOL']);
    return ['terms' => $terms, 'columns' => $built['columns'], 'fitting' => $fitting, 'statistics' => modelStatistics($fitting, $parameters, $inference)];
}

function coefficientInference($model) {
    $fitting = $model['fitting'];
    $statistics = $model['statistics'];
    $coefficients = array_fill(0, $fitting['p'], null);
    foreach ($fitting['accepted'] as $k => $column) {
        $estimate = $fitting['coefficients'][$column];
        $se = $statistics['sigma'] * sqrt($fitting['variance'][$k]);
        $t = $estimate / $se;
        $robustVariance = 0.0;
        for ($i = 0; $i < $fitting['n']; $i++) {
            $epsilon = $fitting['weightedResiduals'][$i];
            $remainder = 1 - $fitting['leverage'][$i];
            $omega = $epsilon * $epsilon / ($remainder * $remainder);
            $robustVariance += $omega * $fitting['g'][$i][$k] * $fitting['g'][$i][$k];
        }
        $robustSe = sqrt($robustVariance);
        $robustT = $estimate / $robustSe;
        $coefficients[$column] = ['estimate' => $estimate, 'se' => $se, 't' => $t, 'p' => tP($t, $statistics['df']),
            'lower' => $estimate - $statistics['critical'] * $se, 'upper' => $estimate + $statistics['critical'] * $se,
            'robustSe' => $robustSe, 'robustT' => $robustT, 'robustP' => tP($robustT, $statistics['df'])];
    }
    return $coefficients;
}

function sequentialTests($model) {
    $fitting = $model['fitting'];
    $statistics = $model['statistics'];
    $tests = [];
    foreach ($model['terms'] as $term) {
        $ss = 0.0;
        $df = 0;
        foreach ($fitting['accepted'] as $k => $column) {
            if ($model['columns'][$column]['term'] === $term['id']) {
                $ss += $fitting['effects'][$k] * $fitting['effects'][$k];
                $df++;
            }
        }
        if ($df === 0) continue;
        $mean = $ss / $df;
        $f = $mean / ($fitting['rss'] / $statistics['df']);
        $tests[] = ['term' => $term, 'df' => $df, 'ss' => $ss, 'mean' => $mean, 'f' => $f, 'p' => fP($f, $df, $statistics['df'])];
    }
    return $tests;
}

function marginalTests($current, $getFit) {
    $tests = [];
    foreach ($current['terms'] as $term) {
        $removable = true;
        foreach ($current['terms'] as $other) if (contained($term, $other)) $removable = false;
        if (!$removable) continue;
        $remaining = array_values(array_filter($current['terms'], fn($other) => $other['id'] !== $term['id']));
        $reduced = $getFit($remaining);
        $df = $current['fitting']['rank'] - $reduced['fitting']['rank'];
        $ss = $reduced['fitting']['rss'] - $current['fitting']['rss'];
        $f = $df > 0 ? ($ss / $df) / ($current['fitting']['rss'] / $current['statistics']['df']) : null;
        $tests[] = ['term' => $term, 'df' => $df, 'ss' => $ss, 'rss' => $reduced['fitting']['rss'], 'f' => $f,
            'p' => $df > 0 ? fP($f, $df, $current['statistics']['df']) : null];
    }
    return $tests;
}

function varianceInflation($model, $parameters) {
    $fitting = $model['fitting'];
    $rows = [];
    for ($k = 1; $k < $fitting['rank']; $k++) {
        $column = $fitting['accepted'][$k];
        $response = $matrix = [];
        $weighted = 0.0;
        foreach ($fitting['matrix'] as $i => $row) {
            $response[] = $row[$column];
            $weighted += $fitting['weights'][$i] * $row[$column];
            $selected = [];
            foreach ($fitting['accepted'] as $j) if ($j !== $column) $selected[] = $row[$j];
            $matrix[] = $selected;
        }
        $auxiliary = fit($matrix, $response, $fitting['weights'], $parameters['RANK_TOL']);
        $mean = $weighted / $model['statistics']['weightSum'];
        $tss = 0.0;
        foreach ($response as $i => $value) $tss += $fitting['weights'][$i] * ($value - $mean) * ($value - $mean);
        $r2 = 1 - $auxiliary['rss'] / $tss;
        $value = 1 / (1 - $r2);
        $rows[] = ['column' => $column, 'value' => $value, 'high' => $value > $parameters['VIF']];
    }
    return $rows;
}

function diagnosticSummary($model, $parameters) {
    $fitting = $model['fitting'];
    $statistics = $model['statistics'];
    $diagnostics = diagnose($fitting, $statistics, $parameters);
    $expanded = [];
    foreach ($fitting['matrix'] as $i => $row) {
        $selected = [];
        foreach ($fitting['accepted'] as $j) $selected[] = $row[$j];
        $value = $fitting['fitted'][$i];
        $selected[] = $value * $value;
        $selected[] = $value * $value * $value;
        $expanded[] = $selected;
    }
    $auxiliary = fit($expanded, $fitting['response'], $fitting['weights'], $parameters['RANK_TOL']);
    $added = $auxiliary['rank'] - $fitting['rank'];
    $df = $fitting['n'] - $auxiliary['rank'];
    $f = (($fitting['rss'] - $auxiliary['rss']) / $added) / ($auxiliary['rss'] / $df);
    $diagnostics['reset'] = ['f' => $f, 'added' => $added, 'df' => $df, 'p' => fP($f, $added, $df)];
    $outlier = 0;
    for ($i = 1; $i < $fitting['n']; $i++) {
        if (abs($diagnostics['rows'][$i]['studentized']) > abs($diagnostics['rows'][$outlier]['studentized'])) $outlier = $i;
    }
    $outlierP = tP($diagnostics['rows'][$outlier]['studentized'], $statistics['df'] - 1);
    $cooks = range(0, $fitting['n'] - 1);
    usort($cooks, function($a, $b) use ($diagnostics) {
        return ($diagnostics['rows'][$b]['cooks'] <=> $diagnostics['rows'][$a]['cooks']) ?: ($a <=> $b);
    });
    $dfbetas = [];
    foreach ($fitting['accepted'] as $k => $column) {
        $largest = 0;
        for ($i = 1; $i < $fitting['n']; $i++) {
            if (abs($diagnostics['rows'][$i]['dfbetas'][$k]) > abs($diagnostics['rows'][$largest]['dfbetas'][$k])) $largest = $i;
        }
        $dfbetas[] = ['column' => $column, 'row' => $largest, 'value' => $diagnostics['rows'][$largest]['dfbetas'][$k]];
    }
    $diagnostics['outlier'] = $outlier;
    $diagnostics['outlierP'] = $outlierP;
    $diagnostics['bonferroni'] = min(1.0, $fitting['n'] * $outlierP);
    $diagnostics['cooks'] = array_slice($cooks, 0, 3);
    $diagnostics['dfbetas'] = $dfbetas;
    $diagnostics['dwLabel'] = $diagnostics['dw'] < $parameters['DURBIN_WATSON'] ? 'positive autocorrelation' : ($diagnostics['dw'] > 4 - $parameters['DURBIN_WATSON'] ? 'negative autocorrelation' : 'no autocorrelation');
    $diagnostics['bpLabel'] = $diagnostics['bp']['p'] < $parameters['BREUSCH_PAGAN'] ? 'heteroscedastic' : 'homoscedastic';
    $diagnostics['jbLabel'] = $diagnostics['jb']['p'] < $parameters['NORMALITY'] ? 'non-normal' : 'normal';
    return $diagnostics;
}

function makePredictions($model, $predictions) {
    $fitting = $model['fitting'];
    $statistics = $model['statistics'];
    $result = [];
    foreach ($predictions['rows'] as $row) {
        if (!predictable($model, $model['levels'], $row)) {
            $result[] = ['row' => $row['number'], 'predictable' => false];
            continue;
        }
        $values = columnValues($model['columns'], $row);
        $prediction = 0.0;
        foreach ($fitting['accepted'] as $column) $prediction += $values[$column] * $fitting['coefficients'][$column];
        $squares = 0.0;
        for ($k = 0; $k < $fitting['rank']; $k++) {
            $sum = 0.0;
            for ($m = 0; $m < $fitting['rank']; $m++) $sum += $values[$fitting['accepted'][$m]] * $fitting['inverse'][$m][$k];
            $squares += $sum * $sum;
        }
        $se = $statistics['sigma'] * sqrt($squares);
        $confidence = $statistics['critical'] * $se;
        $predictionHalf = $statistics['critical'] * sqrt($statistics['sigma'] * $statistics['sigma'] + $se * $se);
        $actual = $row['values'][$model['response']] ?? null;
        $result[] = ['row' => $row['number'], 'predictable' => true, 'prediction' => $prediction, 'se' => $se,
            'confLower' => $prediction - $confidence, 'confUpper' => $prediction + $confidence,
            'predLower' => $prediction - $predictionHalf, 'predUpper' => $prediction + $predictionHalf, 'actual' => $actual,
            'error' => $actual === null ? null : $actual - $prediction,
            'covered' => $actual === null ? null : ($prediction - $predictionHalf <= $actual && $actual <= $prediction + $predictionHalf)];
    }
    return $result;
}

function prepareModel($text, $number, $data, $predictions, $parameters) {
    $model = parseFormula($text, $number);
    $model = array_merge($model, modelRows($model, $data));
    $model = array_merge($model, fitTerms($model, $model['terms'], $parameters, true));
    $model['coefficients'] = coefficientInference($model);
    $model['sequential'] = sequentialTests($model);
    $model['marginal'] = marginalTests($model, fn($terms) => fitTerms($model, $terms, $parameters));
    $model['vif'] = varianceInflation($model, $parameters);
    $model['diagnostics'] = diagnosticSummary($model, $parameters);
    $model['predictions'] = makePredictions($model, $predictions);
    $predicted = $checked = $covered = 0;
    $squares = 0.0;
    foreach ($model['predictions'] as $row) {
        if (!$row['predictable']) continue;
        $predicted++;
        if ($row['error'] !== null) {
            $checked++;
            $squares += $row['error'] * $row['error'];
            if ($row['covered']) $covered++;
        }
    }
    $model['predictionCheck'] = ['predicted' => $predicted, 'checked' => $checked, 'rmse' => $checked ? sqrt($squares / $checked) : null, 'covered' => $covered];
    return $model;
}

function selectionLines($model, $parameters) {
    $original = $model['terms'];
    $cache = [];
    $getFit = function($terms) use (&$cache, $model, $parameters) {
        $mask = 0;
        foreach ($terms as $term) $mask |= 1 << $term['id'];
        if (!isset($cache[$mask])) {
            $result = fitTerms($model, $terms, $parameters);
            $cache[$mask] = ['terms' => $terms, 'fitting' => ['rank' => $result['fitting']['rank'], 'rss' => $result['fitting']['rss']],
                'statistics' => ['df' => $result['statistics']['df'], 'aic' => $result['statistics']['aic'], 'bic' => $result['statistics']['bic']]];
        }
        return $cache[$mask];
    };
    $terms = $original;
    $lines = ['Backward elimination (model 1, alpha ' . fixed($parameters['ALPHA_REMOVE']) . ', rows ' . count($model['rows']) . ')'];
    for ($step = 1; ; $step++) {
        $current = $getFit($terms);
        $lines[] = 'Step ' . $step . ': ' . formatFormula($model, $terms) . ' (RSS ' . fixed($current['fitting']['rss']) . ', df ' . $current['statistics']['df'] . ', AIC ' . fixed($current['statistics']['aic']) . ')';
        if (!$terms) {
            $lines[] = '  stop: no removable terms';
            break;
        }
        $tests = marginalTests($current, $getFit);
        $largest = $tests[0];
        foreach ($tests as $test) {
            $lines[] = '  - ' . $test['term']['name'] . ': F ' . fixed($test['f']) . ' on ' . $test['df'] . ' and ' . $current['statistics']['df'] . ' DF, p-value ' . pValue($test['p']);
            if ($test['p'] > $largest['p']) $largest = $test;
        }
        if ($largest['p'] > $parameters['ALPHA_REMOVE']) {
            $lines[] = '  remove ' . $largest['term']['name'];
            $terms = array_values(array_filter($terms, fn($term) => $term['id'] !== $largest['term']['id']));
        } else {
            $lines[] = '  stop: largest p-value ' . pValue($largest['p']) . ' is not above ' . fixed($parameters['ALPHA_REMOVE']);
            break;
        }
    }
    $lines[] = 'Final model: ' . formatFormula($model, $terms);
    $lines[] = '';
    $lines[] = 'Forward selection by AIC (model 1, rows ' . count($model['rows']) . ')';
    $terms = [];
    for ($step = 1; ; $step++) {
        $current = $getFit($terms);
        $lines[] = 'Step ' . $step . ': ' . formatFormula($model, $terms) . ' (AIC ' . fixed($current['statistics']['aic']) . ')';
        $selectedIds = array_column($terms, 'id');
        $candidates = [];
        foreach ($original as $term) {
            if (in_array($term['id'], $selectedIds, true)) continue;
            $eligible = true;
            foreach ($original as $other) if (contained($other, $term) && !in_array($other['id'], $selectedIds, true)) $eligible = false;
            if ($eligible) $candidates[] = $term;
        }
        if (!$candidates) {
            $lines[] = '  stop: no candidate terms remain';
            break;
        }
        $best = null;
        foreach ($candidates as $candidate) {
            $expanded = array_values(array_filter($original, fn($term) => in_array($term['id'], $selectedIds, true) || $term['id'] === $candidate['id']));
            $result = $getFit($expanded);
            $lines[] = '  + ' . $candidate['name'] . ': AIC ' . fixed($result['statistics']['aic']);
            if ($best === null || $result['statistics']['aic'] < $best['result']['statistics']['aic']) $best = ['candidate' => $candidate, 'terms' => $expanded, 'result' => $result];
        }
        if ($best['result']['statistics']['aic'] < $current['statistics']['aic']) {
            $lines[] = '  add ' . $best['candidate']['name'];
            $terms = $best['terms'];
        } else {
            $lines[] = '  stop: no candidate lowers the AIC';
            break;
        }
    }
    $lines[] = 'Final model: ' . formatFormula($model, $terms);
    $lines[] = '';
    $subsets = [];
    for ($mask = 0; $mask < (1 << count($original)); $mask++) {
        $selected = [];
        foreach ($original as $term) if ($mask & (1 << $term['id'])) $selected[] = $term;
        $hierarchical = true;
        foreach ($selected as $term) foreach ($original as $other) {
            if (contained($other, $term) && !($mask & (1 << $other['id']))) $hierarchical = false;
        }
        if ($hierarchical) $subsets[] = ['mask' => $mask, 'terms' => $selected, 'result' => $getFit($selected)];
    }
    usort($subsets, function($a, $b) {
        return ($a['result']['statistics']['bic'] <=> $b['result']['statistics']['bic']) ?: ($a['mask'] <=> $b['mask']);
    });
    $lines[] = 'Best subsets by BIC (model 1, rows ' . count($model['rows']) . ', subsets ' . count($subsets) . ')';
    foreach (array_slice($subsets, 0, (int)$parameters['BEST_SUBSETS']) as $i => $subset) {
        $result = $subset['result'];
        $lines[] = ($i + 1) . '. BIC ' . fixed($result['statistics']['bic']) . ', AIC ' . fixed($result['statistics']['aic']) . ', rank ' . $result['fitting']['rank'] . ': ' . formatFormula($model, $subset['terms']);
    }
    return $lines;
}

function table($header, $rows) {
    $entries = [['fields' => $header]];
    foreach ($rows as $row) $entries[] = isset($row['fields']) ? $row : ['fields' => $row];
    $widths = array_fill(0, count($header), 0);
    foreach ($entries as $entry) foreach ($entry['fields'] as $i => $field) $widths[$i] = max($widths[$i], strlen((string)$field));
    $lines = [];
    foreach ($entries as $entry) {
        $fields = $entry['fields'];
        $line = str_pad((string)$fields[0], $widths[0], ' ', STR_PAD_RIGHT);
        for ($i = 1; $i < count($fields); $i++) $line .= '  ' . str_pad((string)$fields[$i], $widths[$i], ' ', STR_PAD_LEFT);
        if (!empty($entry['mark'])) $line .= ' ' . $entry['mark'];
        $lines[] = rtrim($line);
    }
    return $lines;
}

function dataSummary($data) {
    $numeric = array_values(array_filter($data['columns'], fn($column) => !$column['categorical']));
    $categorical = array_values(array_filter($data['columns'], fn($column) => $column['categorical']));
    $numericRows = [];
    foreach ($numeric as $column) {
        $values = [];
        foreach ($data['rows'] as $row) if ($row['values'][$column['name']] !== null) $values[] = $row['values'][$column['name']];
        $mean = array_sum($values) / count($values);
        $squares = 0.0;
        foreach ($values as $value) $squares += ($value - $mean) * ($value - $mean);
        $deviation = sqrt($squares / (count($values) - 1));
        $numericRows[] = [$column['name'], count($values), count($data['rows']) - count($values), fixed($mean), fixed($deviation), fixed(min($values)), fixed(max($values))];
    }
    $lines = ['Data: ' . count($data['rows']) . ' rows, ' . count($data['columns']) . ' columns', '', 'Numeric columns:'];
    $lines = array_merge($lines, table(['column', 'n', 'missing', 'Mean', 'SD', 'Min', 'Max'], $numericRows), ['', 'Categorical columns:']);
    foreach ($categorical as $column) {
        $counts = [];
        $present = 0;
        foreach ($data['rows'] as $row) {
            $value = $row['values'][$column['name']];
            if ($value === null) continue;
            $present++;
            $counts[$value] = ($counts[$value] ?? 0) + 1;
        }
        ksort($counts, SORT_STRING);
        $labels = [];
        foreach ($counts as $label => $count) $labels[] = $label . ' ' . $count;
        $lines[] = $column['name'] . ': ' . $present . ' values, ' . (count($data['rows']) - $present) . ' missing, ' . count($counts) . ' levels: ' . implode(', ', $labels);
    }
    $correlations = [];
    foreach ($numeric as $a) {
        $fields = [$a['name']];
        foreach ($numeric as $b) {
            $pairs = [];
            $sumA = $sumB = 0.0;
            foreach ($data['rows'] as $row) {
                $x = $row['values'][$a['name']];
                $y = $row['values'][$b['name']];
                if ($x === null || $y === null) continue;
                $pairs[] = [$x, $y];
                $sumA += $x;
                $sumB += $y;
            }
            $meanA = $sumA / count($pairs);
            $meanB = $sumB / count($pairs);
            $xy = $xx = $yy = 0.0;
            foreach ($pairs as [$aValue, $bValue]) {
                $x = $aValue - $meanA;
                $y = $bValue - $meanB;
                $xy += $x * $y;
                $xx += $x * $x;
                $yy += $y * $y;
            }
            $fields[] = fixed($xy / sqrt($xx * $yy));
        }
        $correlations[] = $fields;
    }
    return array_merge($lines, ['', 'Correlations (pairwise complete observations):'], table(array_merge(['column'], array_column($numeric, 'name')), $correlations), ['']);
}

function modelSummary($model, $totalRows, $parameters) {
    $fitting = $model['fitting'];
    $statistics = $model['statistics'];
    $diagnostics = $model['diagnostics'];
    $columns = $model['columns'];
    $aliases = [];
    $coefficientRows = $confidenceRows = $robustRows = [];
    foreach ($columns as $j => $column) {
        $coefficient = $model['coefficients'][$j];
        if ($coefficient === null) {
            $aliases[] = $column['name'];
            $coefficientRows[] = [$column['name'], 'NA', 'NA', 'NA', 'NA'];
            $confidenceRows[] = [$column['name'], 'NA', 'NA'];
            $robustRows[] = [$column['name'], 'NA', 'NA', 'NA'];
        } else {
            $coefficientRows[] = ['fields' => [$column['name'], fixed($coefficient['estimate']), fixed($coefficient['se']), fixed($coefficient['t']), pValue($coefficient['p'])], 'mark' => significanceMark($coefficient['p'])];
            $confidenceRows[] = [$column['name'], fixed($coefficient['lower']), fixed($coefficient['upper'])];
            $robustRows[] = ['fields' => [$column['name'], fixed($coefficient['robustSe']), fixed($coefficient['robustT']), pValue($coefficient['robustP'])], 'mark' => significanceMark($coefficient['robustP'])];
        }
    }
    $sequentialRows = [];
    foreach ($model['sequential'] as $test) {
        $sequentialRows[] = ['fields' => [$test['term']['name'], $test['df'], fixed($test['ss']), fixed($test['mean']), fixed($test['f']), pValue($test['p'])], 'mark' => significanceMark($test['p'])];
    }
    $sequentialRows[] = ['Residuals', $statistics['df'], fixed($fitting['rss']), fixed($fitting['rss'] / $statistics['df'])];
    $marginalRows = [];
    foreach ($model['marginal'] as $test) {
        $marginalRows[] = ['fields' => [$test['term']['name'], $test['df'], fixed($test['ss']), fixed($test['rss']), fixed($test['f']), pValue($test['p'])], 'mark' => significanceMark($test['p'])];
    }
    $vifRows = [];
    foreach ($model['vif'] as $row) $vifRows[] = ['fields' => [$columns[$row['column']]['name'], fixed($row['value'])], 'mark' => $row['high'] ? 'high' : ''];
    $q = array_map('fixed', $statistics['quantiles']);
    $lines = [
        'Model ' . $model['number'] . ': ' . $model['original'],
        'Terms: ' . implode(', ', array_column($model['terms'], 'name')),
        'Weights: ' . ($model['weight'] ?? 'none'),
        'Observations: ' . $fitting['n'] . ' used, ' . ($totalRows - $fitting['n']) . ' dropped',
        'Columns: ' . $fitting['p'] . ', rank ' . $fitting['rank'] . ', aliased: ' . ($aliases ? implode(', ', $aliases) : 'none'),
        '',
        'Residuals: Min ' . $q[0] . ', 1Q ' . $q[1] . ', Median ' . $q[2] . ', 3Q ' . $q[3] . ', Max ' . $q[4],
        '', 'Coefficients:'
    ];
    $lines = array_merge($lines, table(['term', 'Estimate', 'Std. Error', 't value', 'Pr(>|t|)'], $coefficientRows), [
        '---', "Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1", '',
        'Residual standard error: ' . fixed($statistics['sigma']) . ' on ' . $statistics['df'] . ' degrees of freedom',
        'Multiple R-squared: ' . fixed($statistics['r2']) . ', Adjusted R-squared: ' . fixed($statistics['adjusted']),
        'F-statistic: ' . fixed($statistics['f']) . ' on ' . ($fitting['rank'] - 1) . ' and ' . $statistics['df'] . ' DF, p-value: ' . pValue($statistics['fp']),
        'Log-likelihood: ' . fixed($statistics['loglik']) . ', AIC: ' . fixed($statistics['aic']) . ', BIC: ' . fixed($statistics['bic']),
        'PRESS: ' . fixed($statistics['press']) . ', Predicted R-squared: ' . fixed($statistics['predicted']), '',
        'Confidence intervals (level ' . fixed($parameters['CONFIDENCE']) . ', t ' . fixed($statistics['critical']) . '):'
    ], table(['term', 'Lower', 'Upper'], $confidenceRows), ['', 'Robust standard errors (HC3):'],
        table(['term', 'Std. Error', 't value', 'Pr(>|t|)'], $robustRows), ['', 'Analysis of variance (sequential):'],
        table(['term', 'Df', 'Sum Sq', 'Mean Sq', 'F value', 'Pr(>F)'], $sequentialRows), ['', 'Marginal F tests (drop one term):'],
        table(['term', 'Df', 'Sum Sq', 'RSS', 'F value', 'Pr(>F)'], $marginalRows), ['', 'Variance inflation factors:'],
        table(['column', 'VIF'], $vifRows), ['', 'Diagnostics:',
        'Durbin-Watson: ' . fixed($diagnostics['dw']) . ' (' . $diagnostics['dwLabel'] . ')',
        'Breusch-Pagan: ' . fixed($diagnostics['bp']['value']) . ' on ' . $diagnostics['bp']['df'] . ' DF, p-value: ' . pValue($diagnostics['bp']['p']) . ' (' . $diagnostics['bpLabel'] . ')',
        'Jarque-Bera: ' . fixed($diagnostics['jb']['value']) . ' on 2 DF, p-value: ' . pValue($diagnostics['jb']['p']) . ', skewness ' . fixed($diagnostics['jb']['skewness']) . ', kurtosis ' . fixed($diagnostics['jb']['kurtosis']) . ' (' . $diagnostics['jbLabel'] . ')',
        'RESET (powers 2 and 3): F ' . fixed($diagnostics['reset']['f']) . ' on ' . $diagnostics['reset']['added'] . ' and ' . $diagnostics['reset']['df'] . ' DF, p-value: ' . pValue($diagnostics['reset']['p']),
        'Outlier test: row ' . $model['rows'][$diagnostics['outlier']]['number'] . ', studentized ' . fixed($diagnostics['rows'][$diagnostics['outlier']]['studentized']) . ', unadjusted p-value: ' . pValue($diagnostics['outlierP']) . ', Bonferroni p-value: ' . pValue($diagnostics['bonferroni'])
    ]);
    $counts = ['H' => 0, 'O' => 0, 'C' => 0, 'F' => 0];
    $any = 0;
    foreach ($diagnostics['rows'] as $row) {
        foreach ($counts as $flag => $count) if (str_contains($row['flags'], $flag)) $counts[$flag]++;
        if ($row['flags'] !== '-') $any++;
    }
    $lines[] = 'Flagged rows: leverage ' . $counts['H'] . ', outlier ' . $counts['O'] . ', cooks ' . $counts['C'] . ', dffits ' . $counts['F'] . ', any ' . $any;
    $lines[] = "Largest Cook's distances:";
    foreach ($diagnostics['cooks'] as $i) {
        $row = $diagnostics['rows'][$i];
        $lines[] = 'row ' . $model['rows'][$i]['number'] . ': cooks_d ' . fixed($row['cooks']) . ', leverage ' . fixed($fitting['leverage'][$i]) . ', studentized ' . fixed($row['studentized']) . ', flags ' . $row['flags'];
    }
    $lines[] = 'Largest absolute DFBETAS:';
    $dfbetas = [];
    foreach ($diagnostics['dfbetas'] as $row) $dfbetas[] = [$columns[$row['column']]['name'], $model['rows'][$row['row']]['number'], fixed($row['value'])];
    return array_merge($lines, table(['column', 'row', 'DFBETAS'], $dfbetas));
}

function summaryLines($data, $models, $parameters) {
    $lines = dataSummary($data);
    foreach ($models as $i => $model) {
        if ($i > 0) $lines[] = '';
        $lines = array_merge($lines, modelSummary($model, count($data['rows']), $parameters));
    }
    $rows = [];
    foreach ($models as $model) {
        $s = $model['statistics'];
        $rows[] = [$model['number'], $model['fitting']['n'], $model['fitting']['rank'], fixed($s['sigma']), fixed($s['r2']), fixed($s['adjusted']), fixed($s['predicted']), fixed($s['aic']), fixed($s['bic'])];
    }
    $lines = array_merge($lines, ['', 'Model comparison:'], table(['model', 'n', 'rank', 'sigma', 'R-squared', 'Adj. R-squared', 'Pred. R-squared', 'AIC', 'BIC'], $rows), ['', 'Prediction check:']);
    foreach ($models as $model) {
        $check = $model['predictionCheck'];
        $lines[] = 'model ' . $model['number'] . ': ' . $check['predicted'] . ' predicted, ' . $check['checked'] . ' with actual values, RMSE ' . fixed($check['rmse']) . ', inside prediction interval ' . $check['covered'];
    }
    return $lines;
}

function diagnosticsLines($models) {
    $lines = ['model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags'];
    foreach ($models as $model) foreach ($model['rows'] as $i => $row) {
        $fitting = $model['fitting'];
        $diagnostic = $model['diagnostics']['rows'][$i];
        $lines[] = implode(',', [$model['number'], $row['number'], fixed($fitting['fitted'][$i]), fixed($fitting['residuals'][$i]), fixed($fitting['leverage'][$i]), fixed($diagnostic['studentized']), fixed($diagnostic['cooks']), fixed($diagnostic['dffits']), $diagnostic['flags']]);
    }
    return $lines;
}

function predictionsLines($models) {
    $lines = ['model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered'];
    foreach ($models as $model) foreach ($model['predictions'] as $row) {
        if ($row['predictable']) {
            $values = [fixed($row['prediction']), fixed($row['se']), fixed($row['confLower']), fixed($row['confUpper']), fixed($row['predLower']), fixed($row['predUpper']), fixed($row['actual']), fixed($row['error']), $row['covered'] === null ? 'NA' : ($row['covered'] ? 'yes' : 'no')];
        } else {
            $values = array_fill(0, 9, 'NA');
        }
        $lines[] = implode(',', array_merge([$model['number'], $row['row']], $values));
    }
    return $lines;
}

function plotGrid($values, $studentized, $low, $high, $width, $height, $limit) {
    $counts = array_fill(0, $height, array_fill(0, $width, 0));
    foreach ($values as $i => $value) {
        $column = min((int)floor(($value - $low) / ($high - $low) * $width), $width - 1);
        $row = max(0, min((int)floor(($limit - $studentized[$i]) / (2 * $limit) * $height), $height - 1));
        $counts[$row][$column]++;
    }
    $border = '+' . str_repeat('-', $width) . '+';
    $frame = [$border];
    foreach ($counts as $i => $row) {
        $line = '|';
        foreach ($row as $count) $line .= $count >= 10 ? '*' : ($count > 0 ? (string)$count : ($i === intdiv($height, 2) ? '-' : '.'));
        $frame[] = $line . '|';
    }
    $frame[] = $border;
    return ['counts' => $counts, 'frame' => $frame];
}

function plotLines($models, $parameters) {
    [$width, $height, $limit] = $parameters['PLOT'];
    $lines = [];
    foreach ($models as $index => $model) {
        if ($index > 0) $lines[] = '';
        $fitting = $model['fitting'];
        $studentized = array_column($model['diagnostics']['rows'], 'studentized');
        $low = min($fitting['fitted']);
        $high = max($fitting['fitted']);
        $residual = plotGrid($fitting['fitted'], $studentized, $low, $high, $width, $height, $limit);
        $above = $below = $outside = 0;
        foreach ($studentized as $value) {
            if ($value > 2) $above++;
            if ($value < -2) $below++;
            if (abs($value) > $limit) $outside++;
        }
        $lines = array_merge($lines, ['Model ' . $model['number'] . ': studentized residuals vs fitted values',
            'fitted ' . fixed($low) . ' to ' . fixed($high) . ', studentized ' . fixed(-$limit) . ' to ' . fixed($limit)], $residual['frame'],
            ['points: ' . $fitting['n'] . ', above +2: ' . $above . ', below -2: ' . $below . ', outside range: ' . $outside, 'Histogram of studentized residuals:']);
        $totals = array_map('array_sum', $residual['counts']);
        $maximum = max($totals);
        foreach ($totals as $row => $count) {
            $lower = $limit - 2 * $limit * ($row + 1) / $height;
            $upper = $limit - 2 * $limit * $row / $height;
            $bar = intdiv($count * 40 + $maximum - 1, $maximum);
            $lines[] = fixed($lower) . ' to ' . fixed($upper) . ': ' . $count . ($bar > 0 ? ' ' . str_repeat('#', $bar) : '');
        }
        $maxLeverage = max($fitting['leverage']);
        $leverage = plotGrid($fitting['leverage'], $studentized, 0.0, $maxLeverage, $width, $height, $limit);
        $lines = array_merge($lines, ['Model ' . $model['number'] . ': studentized residuals vs leverage',
            'leverage 0.0000 to ' . fixed($maxLeverage) . ', studentized ' . fixed(-$limit) . ' to ' . fixed($limit)], $leverage['frame']);
    }
    return $lines;
}

$input = readInput();
$models = [];
foreach ($input['models'] as $i => $formula) $models[] = prepareModel($formula, $i + 1, $input['data'], $input['predictions'], $input['parameters']);
$outputs = [
    'summary.txt' => summaryLines($input['data'], $models, $input['parameters']),
    'diagnostics.csv' => diagnosticsLines($models),
    'selection.txt' => selectionLines($models[0], $input['parameters']),
    'predictions.csv' => predictionsLines($models),
    'residual_plot.txt' => plotLines($models, $input['parameters'])
];
foreach ($outputs as $name => $lines) file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
