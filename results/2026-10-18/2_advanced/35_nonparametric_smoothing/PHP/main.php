<?php

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/kernels.php';
require_once __DIR__ . '/loess.php';
require_once __DIR__ . '/spline.php';
require_once __DIR__ . '/selection.php';

function sumValues(array $values): float
{
    $total = 0.0;
    foreach ($values as $value) {
        $total += $value;
    }
    return $total;
}

function squares(array $values): float
{
    $total = 0.0;
    foreach ($values as $value) {
        $total += $value * $value;
    }
    return $total;
}

function residualSum(array $points, array $fitted): float
{
    $total = 0.0;
    foreach ($points as $i => $point) {
        $error = $point->y - $fitted[$i];
        $total += $error * $error;
    }
    return $total;
}

function real(?float $value): string
{
    if ($value === null) {
        return 'NA';
    }
    $text = sprintf('%.4f', $value);
    return $text === '-0.0000' ? '0.0000' : $text;
}

function formatHundredths(int $value): string
{
    $magnitude = abs($value);
    return ($value < 0 ? '-' : '') . intdiv($magnitude, 100) . '.' . sprintf('%02d', $magnitude % 100);
}

function methodList(object $settings): array
{
    $methods = [(object) ['name' => 'linear', 'kind' => 'linear'],
        (object) ['name' => 'running_mean', 'kind' => 'mean', 'candidates' => $settings->windows],
        (object) ['name' => 'running_median', 'kind' => 'median', 'candidates' => $settings->windows]];
    foreach (['nw', 'll'] as $kind) {
        foreach ($settings->kernels as $kernel) {
            $methods[] = (object) ['name' => $kind . '_' . $kernel, 'kind' => $kind, 'kernel' => $kernel, 'candidates' => $settings->bandwidths];
        }
    }
    foreach ($settings->degrees as $degree) {
        $methods[] = (object) ['name' => 'loess' . $degree, 'kind' => 'loess', 'degree' => $degree, 'candidates' => $settings->spans];
    }
    $methods[] = (object) ['name' => 'spline', 'kind' => 'spline', 'candidates' => $settings->lambdas];
    $methods[] = (object) ['name' => 'isotonic', 'kind' => 'isotonic'];
    return $methods;
}

function fitLinear(array $points): object
{
    $n = count($points);
    $xbar = sumValues(array_map(fn($point) => $point->x, $points)) / $n;
    $ybar = sumValues(array_map(fn($point) => $point->y, $points)) / $n;
    $sxx = $sxy = 0.0;
    foreach ($points as $point) {
        $dx = $point->x - $xbar;
        $sxx += $dx * $dx;
        $sxy += $dx * ($point->y - $ybar);
    }
    $b = $sxy / $sxx;
    $a = $ybar - $b * $xbar;
    return (object) ['yhat' => array_map(fn($point) => $a + $b * $point->x, $points), 'edf' => 2.0,
        'lev' => array_map(fn($point) => 1 / $n + ($point->x - $xbar) * ($point->x - $xbar) / $sxx, $points),
        'at' => fn($position) => (object) ['value' => $a + $b * ($position / 100),
            'weights' => array_map(fn($point) => 1 / $n + ($position / 100 - $xbar) * ($point->x - $xbar) / $sxx, $points)]];
}

function nearestPoint(array $points, int $position): int
{
    $nearest = 0;
    for ($i = 1; $i < count($points); $i++) {
        if (abs($points[$i]->X - $position) < abs($points[$nearest]->X - $position)) {
            $nearest = $i;
        }
    }
    return $nearest;
}

function fitRunning(array $points, int $width, bool $median): object
{
    $radii = [];
    $yhat = [];
    $lev = $median ? null : [];
    foreach ($points as $i => $point) {
        $radius = min(intdiv($width - 1, 2), $i, count($points) - 1 - $i);
        $radii[] = $radius;
        $values = array_map(fn($item) => $item->Y, array_slice($points, $i - $radius, 2 * $radius + 1));
        if ($median) {
            sort($values, SORT_NUMERIC);
            $yhat[] = $values[$radius] / 100;
        } else {
            $yhat[] = array_sum($values) / (100 * (2 * $radius + 1));
            $lev[] = 1 / (2 * $radius + 1);
        }
    }
    $at = function ($position) use ($points, $radii, $yhat, $median) {
        $center = nearestPoint($points, $position);
        $weights = null;
        if (!$median) {
            $weights = array_fill(0, count($points), 0.0);
            for ($j = $center - $radii[$center]; $j <= $center + $radii[$center]; $j++) {
                $weights[$j] = 1 / (2 * $radii[$center] + 1);
            }
        }
        return (object) ['value' => $yhat[$center], 'weights' => $weights];
    };
    return (object) ['yhat' => $yhat, 'lev' => $lev, 'edf' => $median ? null : sumValues($lev), 'at' => $at];
}

function fitIsotonic(array $points, string $direction): object
{
    $blocks = [];
    foreach ($points as $i => $point) {
        $blocks[] = (object) ['first' => $i, 'last' => $i, 'total' => $point->Y, 'count' => 1];
        while (count($blocks) >= 2) {
            $left = $blocks[count($blocks) - 2];
            $right = $blocks[count($blocks) - 1];
            $a = $left->total * $right->count;
            $b = $right->total * $left->count;
            if ($direction === 'increasing' ? $a <= $b : $a >= $b) {
                break;
            }
            array_splice($blocks, -2, 2, [(object) ['first' => $left->first, 'last' => $right->last,
                'total' => $left->total + $right->total, 'count' => $left->count + $right->count]]);
        }
    }
    $yhat = array_fill(0, count($points), 0.0);
    foreach ($blocks as $block) {
        $block->value = $block->total / (100 * $block->count);
        for ($i = $block->first; $i <= $block->last; $i++) {
            $yhat[$i] = $block->value;
        }
    }
    $at = function ($position) use ($points, $yhat) {
        $index = 0;
        while ($index + 1 < count($points) && $points[$index + 1]->X <= $position) {
            $index++;
        }
        return (object) ['value' => $yhat[$index], 'weights' => null];
    };
    return (object) ['yhat' => $yhat, 'edf' => (float) count($blocks), 'lev' => null, 'blocks' => $blocks, 'direction' => $direction, 'at' => $at];
}

function fitFull(object $method, ?object $candidate, array $points, int $iterations = 0): object
{
    if ($method->kind === 'linear') {
        return fitLinear($points);
    }
    if ($method->kind === 'mean' || $method->kind === 'median') {
        return fitRunning($points, $candidate->value, $method->kind === 'median');
    }
    if ($method->kind === 'nw' || $method->kind === 'll') {
        return fitKernel($points, $method->kind, $method->kernel, $candidate->hundredths);
    }
    if ($method->kind === 'loess') {
        return fitLoess($points, $method->degree, $candidate->hundredths, $iterations);
    }
    return fitSpline($points, $candidate->value);
}

function subsetEstimator(object $method, ?object $candidate, array $points, ?string $direction): callable
{
    if ($method->kind === 'nw' || $method->kind === 'll') {
        return fn($position) => kernelEstimate($points, $method->kind, $method->kernel, $candidate->hundredths, $position)->value;
    }
    if ($method->kind === 'loess') {
        $robustness = array_fill(0, count($points), 1.0);
        return fn($position) => localFit($points, $method->degree, $candidate->hundredths, $robustness, $position)->value;
    }
    if ($method->kind === 'spline') {
        $fit = fitSpline($points, $candidate->value, false);
    } elseif ($method->kind === 'isotonic') {
        $fit = fitIsotonic($points, $direction);
    } else {
        $fit = fitFull($method, $candidate, $points);
    }
    return fn($position) => ($fit->at)($position)->value;
}

function leaveOneOut(object $method, ?object $candidate, array $points, ?string $direction = null): ?float
{
    $predictions = [];
    foreach ($points as $i => $point) {
        $subset = $points;
        array_splice($subset, $i, 1);
        $estimate = subsetEstimator($method, $candidate, $subset, $direction);
        $predictions[] = $estimate($point->X);
    }
    return crossValidation(array_map(fn($point) => $point->y, $points), $predictions);
}

function kfold(object $method, ?object $candidate, array $points, ?string $direction, int $groups): ?float
{
    $predictions = array_fill(0, count($points), null);
    for ($group = 0; $group < $groups; $group++) {
        $subset = [];
        foreach ($points as $i => $point) {
            if ($i % $groups !== $group) {
                $subset[] = $point;
            }
        }
        $estimate = subsetEstimator($method, $candidate, $subset, $direction);
        for ($i = $group; $i < count($points); $i += $groups) {
            $predictions[$i] = $estimate($points[$i]->X);
        }
    }
    return crossValidation(array_map(fn($point) => $point->y, $points), $predictions);
}

function fitMethods(object $series, object $settings, array $methods): array
{
    $points = $series->points;
    $models = [];
    foreach ($methods as $method) {
        $chosen = null;
        $selected = -1;
        $parameter = '-';
        $candidates = [];
        $increasingRSS = $decreasingRSS = null;
        if ($method->kind === 'linear') {
            $fit = fitLinear($points);
            $loo = leaveOneOut($method, null, $points);
        } elseif ($method->kind === 'isotonic') {
            if ($series->mode === 'auto') {
                $increasing = fitIsotonic($points, 'increasing');
                $decreasing = fitIsotonic($points, 'decreasing');
                $increasingRSS = residualSum($points, $increasing->yhat);
                $decreasingRSS = residualSum($points, $decreasing->yhat);
                $fit = $increasingRSS <= $decreasingRSS ? $increasing : $decreasing;
            } else {
                $fit = fitIsotonic($points, $series->mode);
            }
            $parameter = $fit->direction;
            $loo = leaveOneOut($method, null, $points, $fit->direction);
        } else {
            $evaluated = [];
            foreach ($method->candidates as $candidate) {
                $candidateFit = fitFull($method, $candidate, $points);
                $score = $method->kind === 'spline'
                    ? generalized(array_map(fn($point) => $point->y, $points), $candidateFit->yhat, $candidateFit->edf)
                    : leaveOneOut($method, $candidate, $points);
                $evaluated[] = (object) ['candidate' => $candidate, 'fit' => $candidateFit, 'score' => $score, 'edf' => $candidateFit->edf];
            }
            $selected = selectCandidate($evaluated);
            $winner = $evaluated[$selected];
            $chosen = $winner->candidate;
            $parameter = $chosen->text;
            $fit = $method->kind === 'loess' && $settings->robustIterations > 0
                ? fitFull($method, $chosen, $points, $settings->robustIterations) : $winner->fit;
            $loo = $method->kind === 'spline' ? leaveOneOut($method, $chosen, $points) : $winner->score;
            $candidates = array_map(fn($item) => (object) ['parameter' => $item->candidate->text, 'score' => $item->score, 'edf' => $item->edf], $evaluated);
        }
        $model = clone $fit;
        $model->method = $method;
        $model->name = $method->name;
        $model->order = count($models);
        $model->chosen = $chosen;
        $model->parameter = $parameter;
        $model->selected = $selected;
        $model->candidates = $candidates;
        $model->loo = $loo;
        $model->increasingRSS = $increasingRSS;
        $model->decreasingRSS = $decreasingRSS;
        $model->kfold = kfold($method, $chosen, $points, $fit->direction ?? null, $settings->folds);
        $models[] = $model;
    }
    return $models;
}

function turningCount(array $estimates): int
{
    $values = [];
    foreach ($estimates as $item) {
        if ($item->value !== null) {
            $values[] = $item->value;
        }
    }
    $previousSign = 0;
    $count = 0;
    for ($i = 1; $i < count($values); $i++) {
        $delta = $values[$i] - $values[$i - 1];
        if ($delta == 0) {
            continue;
        }
        $sign = $delta > 0 ? 1 : -1;
        if ($previousSign !== 0 && $sign !== $previousSign) {
            $count++;
        }
        $previousSign = $sign;
    }
    return $count;
}

function diagnostics(array $points, object $model, float $linearRSS): object
{
    $n = count($points);
    $errors = [];
    foreach ($points as $i => $point) {
        $errors[] = $point->y - $model->yhat[$i];
    }
    $rss = squares($errors);
    $ybar = sumValues(array_map(fn($point) => $point->y, $points)) / $n;
    $tss = squares(array_map(fn($point) => $point->y - $ybar, $points));
    $df = $model->edf === null ? null : $n - $model->edf;
    $rse = $df === null ? null : sqrt($rss / $df);
    $nonlinear = $model->name !== 'linear' && $model->edf !== null && $model->edf > 2
        ? (($linearRSS - $rss) / ($model->edf - 2)) / ($rss / $df) : null;
    $meanError = sumValues($errors) / $n;
    $centered = array_map(fn($value) => $value - $meanError, $errors);
    $denominator = squares($centered);
    $acf = [];
    for ($lag = 1; $lag <= 5; $lag++) {
        $numerator = 0.0;
        for ($i = 0; $i < $n - $lag; $i++) {
            $numerator += $centered[$i] * $centered[$i + $lag];
        }
        $acf[] = $numerator / $denominator;
    }
    $successive = 0.0;
    $positive = $negative = $runs = $previousSign = $largest = 0;
    foreach ($errors as $i => $error) {
        if ($i > 0) {
            $delta = $error - $errors[$i - 1];
            $successive += $delta * $delta;
        }
        if (abs($error) > abs($errors[$largest])) {
            $largest = $i;
        }
        if ($error == 0) {
            continue;
        }
        $sign = $error > 0 ? 1 : -1;
        if ($sign > 0) {
            $positive++;
        } else {
            $negative++;
        }
        if ($sign !== $previousSign) {
            $runs++;
        }
        $previousSign = $sign;
    }
    $nonzero = $positive + $negative;
    $pairs = 2 * $positive * $negative;
    $mu = 1 + $pairs / $nonzero;
    $variance = $pairs * ($pairs - $nonzero) / ($nonzero * $nonzero * ($nonzero - 1));
    $sorted = $errors;
    sort($sorted, SORT_NUMERIC);
    $quantiles = [];
    for ($k = 0; $k <= 4; $k++) {
        $j = intdiv(($n - 1) * $k, 4);
        $remainder = ($n - 1) * $k - 4 * $j;
        $quantiles[] = $remainder === 0 ? $sorted[$j] : $sorted[$j] + $remainder / 4 * ($sorted[$j + 1] - $sorted[$j]);
    }
    return (object) ['errors' => $errors, 'rss' => $rss, 'df' => $df, 'rse' => $rse, 'r2' => 1 - $rss / $tss,
        'nonlinear' => $nonlinear, 'acf' => $acf, 'dw' => $successive / $rss, 'positive' => $positive, 'negative' => $negative,
        'runs' => $runs, 'runsZ' => ($runs - $mu) / sqrt($variance), 'largest' => $largest, 'quantiles' => $quantiles, 'turning' => turningCount($model->grid)];
}

function findModel(array $models, string $name): object
{
    foreach ($models as $model) {
        if ($model->name === $name) {
            return $model;
        }
    }
}

function compareFits(array $models, array $grid, object $settings): object
{
    $ranking = $models;
    usort($ranking, fn($a, $b) => ($a->loo <=> $b->loo) ?: ($a->order <=> $b->order));
    $best = $ranking[0];
    $agreements = [];
    foreach ($models as $model) {
        if ($model === $best) {
            continue;
        }
        $count = 0;
        $total = 0.0;
        $maximum = null;
        $position = 0;
        foreach ($grid as $k => $point) {
            if ($model->grid[$k]->value === null || $best->grid[$k]->value === null) {
                continue;
            }
            $delta = abs($model->grid[$k]->value - $best->grid[$k]->value);
            $count++;
            $total += $delta * $delta;
            if ($maximum === null || $delta > $maximum) {
                $maximum = $delta;
                $position = $point;
            }
        }
        $agreements[] = (object) ['name' => $model->name, 'count' => $count, 'rms' => sqrt($total / $count), 'maximum' => $maximum, 'position' => $position];
    }
    $spline = findModel($models, 'spline');
    $maximum = $minimum = null;
    $maxPosition = $minPosition = 0;
    for ($k = 1; $k < count($grid) - 1; $k++) {
        $slope = ($spline->grid[$k + 1]->value - $spline->grid[$k - 1]->value) / (($grid[$k + 1] - $grid[$k - 1]) / 100);
        if ($maximum === null || $slope > $maximum) {
            $maximum = $slope;
            $maxPosition = $grid[$k];
        }
        if ($minimum === null || $slope < $minimum) {
            $minimum = $slope;
            $minPosition = $grid[$k];
        }
    }
    $outlierMethod = null;
    foreach ($ranking as $model) {
        if ($model->lev !== null) {
            $outlierMethod = $model;
            break;
        }
    }
    $standardized = [];
    foreach ($outlierMethod->lev as $i => $lev) {
        if ($lev >= 1) {
            continue;
        }
        $t = $outlierMethod->diagnostics->errors[$i] / ($outlierMethod->diagnostics->rse * sqrt(1 - $lev));
        $cook = $t * $t * $lev / ((1 - $lev) * $outlierMethod->edf);
        $standardized[] = (object) ['index' => $i, 't' => $t, 'cook' => $cook];
    }
    $outliers = array_values(array_filter($standardized, fn($item) => abs($item->t) > $settings->threshold / 100));
    usort($outliers, fn($a, $b) => (abs($b->t) <=> abs($a->t)) ?: ($a->index <=> $b->index));
    $influence = $standardized;
    usort($influence, fn($a, $b) => ($b->cook <=> $a->cook) ?: ($a->index <=> $b->index));
    $influence = array_slice($influence, 0, 3);
    return (object) ['ranking' => $ranking, 'best' => $best, 'agreements' => $agreements,
        'slope' => (object) compact('maximum', 'minimum', 'maxPosition', 'minPosition'),
        'outlierMethod' => $outlierMethod, 'standardized' => $standardized, 'outliers' => $outliers, 'influence' => $influence];
}

function variabilityBands(array $points, array $models, object $settings): array
{
    $bands = [];
    foreach ($settings->bandMethods as $name) {
        $model = findModel($models, $name);
        $rse = $model->diagnostics->rse;
        $total = 0.0;
        $count = 0;
        $values = [];
        foreach ($model->grid as $estimate) {
            if ($estimate->value === null) {
                $values[] = (object) ['fit' => null, 'se' => null, 'lower' => null, 'upper' => null];
                continue;
            }
            $se = $rse * sqrt(squares($estimate->weights));
            $total += $se;
            $count++;
            $values[] = (object) ['fit' => $estimate->value, 'se' => $se,
                'lower' => $estimate->value - $settings->bandZ * $se, 'upper' => $estimate->value + $settings->bandZ * $se];
        }
        $coverage = 0;
        foreach ($points as $i => $point) {
            $estimate = ($model->at)($point->X);
            $se = $rse * sqrt(squares($estimate->weights));
            if (abs($model->diagnostics->errors[$i]) <= $settings->bandZ * sqrt($rse * $rse + $se * $se)) {
                $coverage++;
            }
        }
        $bands[] = (object) ['name' => $name, 'values' => $values, 'meanSE' => $total / $count, 'coverage' => $coverage];
    }
    return $bands;
}

function bootstrapIntervals(object $model, array $grid, object $settings, callable $draw): array
{
    $residuals = $model->diagnostics->errors;
    $mean = sumValues($residuals) / count($residuals);
    $centered = array_map(fn($value) => $value - $mean, $residuals);
    $samples = array_fill(0, count($grid), []);
    for ($b = 0; $b < $settings->bootstrap; $b++) {
        $values = [];
        foreach ($residuals as $i => $error) {
            $values[] = $model->yhat[$i] + $centered[$draw() % count($residuals)];
        }
        $fit = $model->system->fit($values);
        foreach ($grid as $k => $position) {
            $samples[$k][] = $model->system->evaluate($fit, $position);
        }
    }
    $result = [];
    foreach ($samples as $k => $values) {
        $average = sumValues($values) / $settings->bootstrap;
        $se = sqrt(squares(array_map(fn($value) => $value - $average, $values)) / ($settings->bootstrap - 1));
        sort($values, SORT_NUMERIC);
        $result[] = (object) ['fit' => $model->grid[$k]->value, 'se' => $se,
            'lower' => $values[$settings->trim], 'upper' => $values[$settings->bootstrap - $settings->trim - 1]];
    }
    return $result;
}

function diagnosticsBlock(object $result, object $settings): string
{
    $series = $result->series;
    $points = $series->points;
    $comparison = $result->comparison;
    $lines = ['series ' . $series->name . ' n ' . count($points) . ' x ' . formatHundredths($points[0]->X)
        . ' ' . formatHundredths($points[count($points) - 1]->X) . ' y ' . formatHundredths($result->minY) . ' ' . formatHundredths($result->maxY)];
    foreach ($result->models as $model) {
        $d = $model->diagnostics;
        $heading = 'method ' . $model->name . ' parameter ' . $model->parameter . ' loo ' . real($model->loo);
        if ($model->name === 'spline') {
            $heading .= ' gcv ' . real($model->candidates[$model->selected]->score);
        }
        $lines[] = $heading;
        $lines[] = '  rss ' . real($d->rss) . ' edf ' . real($model->edf) . ' df ' . real($d->df)
            . ' rse ' . real($d->rse) . ' r2 ' . real($d->r2) . ' f_nonlinear ' . real($d->nonlinear);
        $lines[] = '  acf ' . implode(' ', array_map('real', $d->acf)) . ' dw ' . real($d->dw);
        $lines[] = '  runs ' . $d->runs . ' positive ' . $d->positive . ' negative ' . $d->negative . ' z ' . real($d->runsZ);
        $lines[] = '  max_residual ' . real($d->errors[$d->largest]) . ' at ' . formatHundredths($points[$d->largest]->X) . ' turning ' . $d->turning;
        $lines[] = '  quantiles ' . implode(' ', array_map('real', $d->quantiles));
        if ($model->method->kind === 'loess') {
            foreach ($model->records as $record) {
                $lines[] = '  robust ' . $record->iteration . ' scale ' . real($record->scale) . ' zero_weight ' . $record->zeros . ' max_change ' . real($record->change);
            }
            $zeros = [];
            foreach ($points as $i => $point) {
                if ($model->robustness[$i] == 0) {
                    $zeros[] = formatHundredths($point->X);
                }
            }
            $lines[] = '  zero_weight_points ' . ($zeros ? implode(' ', $zeros) : 'none');
        }
    }
    $lines[] = 'ranking';
    foreach ($comparison->ranking as $i => $model) {
        $lines[] = '  ' . ($i + 1) . ' ' . $model->name . ' ' . real($model->loo) . ' kfold ' . real($model->kfold);
    }
    $lines[] = 'agreement with ' . $comparison->best->name;
    foreach ($comparison->agreements as $item) {
        $lines[] = '  ' . $item->name . ' points ' . $item->count . ' rms ' . real($item->rms) . ' max ' . real($item->maximum)
            . ' at ' . formatHundredths($item->position);
    }
    $slope = $comparison->slope;
    $lines[] = 'slope spline max ' . real($slope->maximum) . ' at ' . formatHundredths($slope->maxPosition)
        . ' min ' . real($slope->minimum) . ' at ' . formatHundredths($slope->minPosition);
    $outlier = $comparison->outlierMethod;
    $lines[] = 'outliers method ' . $outlier->name . ' threshold ' . formatHundredths($settings->threshold);
    if (!$comparison->outliers) {
        $lines[] = '  none';
    }
    foreach ($comparison->outliers as $item) {
        $point = $points[$item->index];
        $lines[] = '  x ' . formatHundredths($point->X) . ' y ' . formatHundredths($point->Y) . ' fit ' . real($outlier->yhat[$item->index])
            . ' residual ' . real($outlier->diagnostics->errors[$item->index]) . ' standardized ' . real($item->t);
    }
    $lines[] = 'influence method ' . $outlier->name;
    foreach ($comparison->influence as $item) {
        $lines[] = '  x ' . formatHundredths($points[$item->index]->X) . ' lev ' . real($outlier->lev[$item->index]) . ' cook ' . real($item->cook);
    }
    $lines[] = 'bands';
    foreach ($result->bands as $band) {
        $lines[] = '  ' . $band->name . ' mean_se ' . real($band->meanSE) . ' coverage ' . $band->coverage . ' of ' . count($points);
    }
    return implode("\n", $lines);
}

function isotonicBlock(object $result): string
{
    $series = $result->series;
    $model = findModel($result->models, 'isotonic');
    $heading = 'series ' . $series->name . ' direction ' . $model->direction . ' mode ' . $series->mode;
    if ($series->mode === 'auto') {
        $heading .= ' rss_increasing ' . real($model->increasingRSS) . ' rss_decreasing ' . real($model->decreasingRSS);
    }
    $lines = [$heading, 'blocks ' . count($model->blocks) . ' rss ' . real($model->diagnostics->rss) . ' loo ' . real($model->loo)];
    foreach ($model->blocks as $i => $block) {
        $lines[] = 'block ' . ($i + 1) . ' x ' . formatHundredths($series->points[$block->first]->X) . ' '
            . formatHundredths($series->points[$block->last]->X) . ' count ' . $block->count . ' value ' . real($block->value);
    }
    return implode("\n", $lines);
}

function frame(array $cells): array
{
    $border = '+' . str_repeat('-', count($cells[0])) . '+';
    $lines = [$border];
    foreach ($cells as $row) {
        $lines[] = '|' . implode('', $row) . '|';
    }
    $lines[] = $border;
    return $lines;
}

function histogram(array $standardized): array
{
    $counts = array_fill(0, 14, 0);
    foreach ($standardized as $item) {
        $t = $item->t;
        $bin = 0;
        if ($t >= 3) {
            $bin = 13;
        } elseif ($t >= -3) {
            $bin = 1;
            while ($t >= -3 + 0.5 * $bin) {
                $bin++;
            }
        }
        $counts[$bin]++;
    }
    $lines = [];
    foreach ($counts as $bin => $count) {
        $lower = $bin === 0 ? '-inf' : formatHundredths(-300 + 50 * ($bin - 1));
        $upper = $bin === 13 ? 'inf' : formatHundredths(-300 + 50 * $bin);
        $lines[] = $lower . ' ' . $upper . ' ' . $count . ' |' . str_repeat('#', $count);
    }
    return $lines;
}

function plotBlock(object $result, object $settings): string
{
    $series = $result->series;
    $models = $result->models;
    $comparison = $result->comparison;
    $width = $settings->width;
    $height = $settings->height;
    $points = $series->points;
    $firstX = $points[0]->X;
    $lastX = $points[count($points) - 1]->X;
    $minY = $result->minY;
    $maxY = $result->maxY;
    $ymin = $minY / 100;
    $ymax = $maxY / 100;
    $blank = fn() => array_fill(0, $height, array_fill(0, $width, ' '));
    $clampRow = fn($value) => max(0, min($height - 1, (int) floor($value)));
    $column = fn($point) => min($width - 1, intdiv($width * ($point->X - $firstX), $lastX - $firstX));
    $cells = $blank();
    foreach ($points as $point) {
        $row = min($height - 1, intdiv($height * ($maxY - $point->Y), $maxY - $minY));
        $cells[$row][$column($point)] = '.';
    }
    foreach ($settings->plotMethods as $i => $name) {
        $model = findModel($models, $name);
        $digit = (string) ($i + 1);
        for ($c = 0; $c < $width; $c++) {
            $position = $firstX + intdiv((2 * $c + 1) * ($lastX - $firstX), 2 * $width);
            $value = ($model->at)($position)->value;
            if ($value === null) {
                continue;
            }
            $row = $clampRow($height * ($ymax - $value) / ($ymax - $ymin));
            $previous = $cells[$row][$c];
            $cells[$row][$c] = $previous === ' ' || $previous === '.' || $previous === $digit ? $digit : '*';
        }
    }
    $data = $curve = $overlap = 0;
    foreach ($cells as $row) {
        foreach ($row as $character) {
            if ($character === '.') {
                $data++;
            } elseif ($character === '*') {
                $overlap++;
            } elseif ($character >= '1' && $character <= '9') {
                $curve++;
            }
        }
    }
    $residuals = $blank();
    $residuals[intdiv($height, 2)] = array_fill(0, $width, '-');
    $errors = $comparison->best->diagnostics->errors;
    $limit = 0.0;
    foreach ($errors as $error) {
        $limit = max($limit, abs($error));
    }
    foreach ($points as $i => $point) {
        $residuals[$clampRow($height * (($limit - $errors[$i]) / (2 * $limit)))][$column($point)] = 'o';
    }
    $legend = [];
    foreach ($settings->plotMethods as $i => $name) {
        $legend[] = ($i + 1) . ' ' . $name;
    }
    $lines = array_merge(['plot ' . $series->name . ' size ' . $width . 'x' . $height . ' x ' . formatHundredths($firstX) . ' '
        . formatHundredths($lastX) . ' y ' . formatHundredths($minY) . ' ' . formatHundredths($maxY),
        'legend . data ' . implode(' ', $legend)], frame($cells),
        ['cells data ' . $data . ' curve ' . $curve . ' overlap ' . $overlap, '',
            'residuals ' . $series->name . ' method ' . $comparison->best->name . ' limit ' . real($limit)], frame($residuals),
        ['', 'histogram ' . $series->name . ' method ' . $comparison->outlierMethod->name], histogram($comparison->standardized));
    return implode("\n", $lines);
}

function processSeries(object $series, object $settings, array $methods, callable $draw): object
{
    $points = $series->points;
    $grid = [];
    for ($k = 0; $k < $settings->gridPoints; $k++) {
        $grid[] = $points[0]->X + intdiv($k * ($points[count($points) - 1]->X - $points[0]->X), $settings->gridPoints - 1);
    }
    $models = fitMethods($series, $settings, $methods);
    $linearRSS = residualSum($points, $models[0]->yhat);
    foreach ($models as $model) {
        $model->grid = array_map(fn($position) => ($model->at)($position), $grid);
        $model->diagnostics = diagnostics($points, $model, $linearRSS);
    }
    $comparison = compareFits($models, $grid, $settings);
    $bands = variabilityBands($points, $models, $settings);
    $bootstrap = bootstrapIntervals(findModel($models, 'spline'), $grid, $settings, $draw);
    $yValues = array_map(fn($point) => $point->Y, $points);
    return (object) ['series' => $series, 'grid' => $grid, 'models' => $models, 'comparison' => $comparison, 'bands' => $bands,
        'bootstrap' => $bootstrap, 'minY' => min($yValues), 'maxY' => max($yValues)];
}

$input = readInput();
$settings = $input->settings;
$methods = methodList($settings);
$state = $settings->seed;
$draw = function () use (&$state): int {
    $state = (48271 * $state) % 2147483647;
    return $state;
};
$results = [];
$byName = [];
foreach ($input->series as $series) {
    $result = processSeries($series, $settings, $methods, $draw);
    $results[] = $result;
    $byName[$series->name] = $result;
}
$selectionLines = ['series,method,parameter,score,edf,selected'];
$estimatesHeader = 'series,x,' . implode(',', array_map(fn($method) => $method->name, $methods));
$fitLines = [$estimatesHeader];
$predictionLines = [$estimatesHeader];
$bandLines = ['series,method,x,fit,se,lower,upper'];
foreach ($results as $result) {
    $name = $result->series->name;
    foreach ($result->models as $model) {
        foreach ($model->candidates as $i => $candidate) {
            $selectionLines[] = implode(',', [$name, $model->name, $candidate->parameter, real($candidate->score),
                real($candidate->edf), $i === $model->selected ? 1 : 0]);
        }
    }
    foreach ($result->grid as $k => $position) {
        $values = array_map(fn($model) => real($model->grid[$k]->value), $result->models);
        $fitLines[] = implode(',', array_merge([$name, formatHundredths($position)], $values));
    }
    $bands = array_merge($result->bands, [(object) ['name' => 'spline_bootstrap', 'values' => $result->bootstrap]]);
    foreach ($bands as $band) {
        foreach ($band->values as $k => $value) {
            $bandLines[] = implode(',', [$name, $band->name, formatHundredths($result->grid[$k]),
                real($value->fit), real($value->se), real($value->lower), real($value->upper)]);
        }
    }
}
foreach ($input->tests as $test) {
    $result = $byName[$test->name];
    $values = array_map(fn($model) => real(($model->at)($test->X)->value), $result->models);
    $predictionLines[] = implode(',', array_merge([$test->name, formatHundredths($test->X)], $values));
}
$diagnosticsBlocks = array_map(fn($result) => diagnosticsBlock($result, $settings), $results);
$isotonicBlocks = array_map('isotonicBlock', $results);
$plotBlocks = array_map(fn($name) => plotBlock($byName[$name], $settings), $settings->plotSeries);
$files = ['selection.csv' => implode("\n", $selectionLines), 'fits.csv' => implode("\n", $fitLines),
    'predictions.csv' => implode("\n", $predictionLines), 'bands.csv' => implode("\n", $bandLines),
    'diagnostics.txt' => implode("\n\n", $diagnosticsBlocks), 'isotonic.txt' => implode("\n\n", $isotonicBlocks),
    'plots.txt' => implode("\n\n", $plotBlocks)];
if (!is_dir('output')) {
    mkdir('output', 0777, true);
}
foreach ($files as $name => $contents) {
    file_put_contents('output/' . $name, $contents . "\n");
}
