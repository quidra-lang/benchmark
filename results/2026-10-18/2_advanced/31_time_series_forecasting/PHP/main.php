<?php

require_once __DIR__ . '/series_io.php';
require_once __DIR__ . '/decomposition.php';
require_once __DIR__ . '/smoothing.php';
require_once __DIR__ . '/autoregression.php';
require_once __DIR__ . '/evaluation.php';

const METHODS = ['naive', 'snaive', 'drift', 'ses', 'holt', 'damped', 'hw_add', 'hw_mult', 'decomp_add', 'decomp_mult', 'ar'];
const DIFFERENCES = ['none', 'first', 'seasonal', 'both'];

function squaredSum(array $values): float
{
    $total = 0.0;
    foreach ($values as $value) {
        $total += $value * $value;
    }
    return $total;
}

function interpolate(array $raw): array
{
    $values = $raw;
    for ($t = 0; $t < count($raw); $t++) {
        if ($raw[$t] !== null) {
            continue;
        }
        $before = $t - 1;
        $after = $t + 1;
        while ($raw[$after] === null) {
            $after++;
        }
        for ($i = $t; $i < $after; $i++) {
            $values[$i] = $raw[$before] + ($raw[$after] - $raw[$before]) * ($i - $before) / ($after - $before);
        }
        $t = $after - 1;
    }
    return $values;
}

function prepareSeries(object $series, object $settings): object
{
    $values = interpolate($series->raw);
    $decomposition = decompose($values, $settings->season);
    $missing = $pastEvents = $lifts = [];
    foreach ($series->raw as $t => $value) {
        if ($value === null) {
            $missing[$t] = true;
        }
    }
    foreach ($values as $t => $value) {
        $kind = $series->events[$series->periods[$t]] ?? null;
        if ($kind === null) {
            continue;
        }
        $pastEvents[$t] = $kind;
        if (!isset($lifts[$kind])) {
            $lifts[$kind] = (object) ['count' => 0, 'total' => 0.0];
        }
        $entry = $lifts[$kind];
        $entry->count++;
        $entry->total += $value / ($decomposition->trend[$t] + $decomposition->add[$t % $settings->season]);
    }
    foreach ($lifts as $entry) {
        $entry->lift = $entry->total / $entry->count;
    }
    $residuals = array_map(fn($t) => $decomposition->residualAdd[$t], $decomposition->defined);
    $residualMean = mean($residuals);
    $residualVariance = sampleVariance($residuals);
    $deviation = sqrt($residualVariance);
    $outliers = [];
    foreach ($decomposition->defined as $t) {
        if (isset($missing[$t]) || isset($pastEvents[$t])) {
            continue;
        }
        $difference = $decomposition->residualAdd[$t] - $residualMean;
        if (abs($difference) > $settings->outlier * $deviation) {
            $outliers[$t] = $difference / $deviation;
        }
    }
    $cleaned = [];
    foreach ($values as $t => $value) {
        $cleaned[] = isset($outliers[$t]) || isset($pastEvents[$t]) ?
            $decomposition->trend[$t] + $decomposition->add[$t % $settings->season] : $value;
    }
    $trendVariance = sampleVariance(array_map(fn($t) => $decomposition->trend[$t] + $decomposition->residualAdd[$t], $decomposition->defined));
    $seasonalVariance = sampleVariance(array_map(fn($t) => $decomposition->add[$t % $settings->season] + $decomposition->residualAdd[$t], $decomposition->defined));
    $strengthTrend = max(0.0, 1.0 - $residualVariance / $trendVariance);
    $strengthSeasonal = max(0.0, 1.0 - $residualVariance / $seasonalVariance);
    $periods = $series->periods;
    for ($k = 0; $k < $settings->horizon; $k++) {
        $periods[] = nextMonth($periods[count($periods) - 1]);
    }
    return (object) ['name' => $series->name, 'raw' => $series->raw, 'events' => $series->events, 'inventory' => $series->inventory,
        'periods' => $periods, 'values' => $values, 'cleaned' => $cleaned, 'decomposition' => $decomposition, 'missing' => $missing,
        'pastEvents' => $pastEvents, 'lifts' => $lifts, 'outliers' => $outliers, 'strengthTrend' => $strengthTrend, 'strengthSeasonal' => $strengthSeasonal];
}

function parameterGrid(array $names, object $settings, int $position = 0, array $current = []): Generator
{
    if ($position === count($names)) {
        yield $current;
        return;
    }
    $name = $names[$position];
    foreach ($settings->$name as $value) {
        $next = $current;
        $next[$name] = $value;
        yield from parameterGrid($names, $settings, $position + 1, $next);
    }
}

function regressionForecast(object $model, int $time): float
{
    $seasonal = $model->seasonal[$time % count($model->seasonal)];
    return $model->name === 'decomp_add' ? $model->intercept + $model->slope * ($time + 1) + $seasonal :
        ($model->intercept + $model->slope * ($time + 1)) * $seasonal;
}

function fitAutoregression(object $model, object $settings): void
{
    $variants = [];
    foreach (DIFFERENCES as $kind) {
        $differenced = difference($model->values, $kind, $settings->season);
        $correlation = autocorrelation($differenced->values, $settings->maxLag);
        $variants[] = (object) ['kind' => $kind, 'values' => $differenced->values, 'offset' => $differenced->offset,
            'mean' => $correlation->mean, 'variance' => $correlation->variance, 'correlations' => $correlation->correlations];
    }
    $chosen = $variants[0];
    foreach (array_slice($variants, 1) as $candidate) {
        if ($candidate->variance < $chosen->variance) {
            $chosen = $candidate;
        }
    }
    $recursion = durbinLevinson($chosen->correlations);
    $aic = [];
    $order = 0;
    for ($p = 0; $p <= $settings->maxAr; $p++) {
        $aic[] = count($chosen->values) * log($chosen->variance * $recursion->variances[$p]) + 2 * $p;
        if ($aic[$p] < $aic[$order]) {
            $order = $p;
        }
    }
    $model->difference = $chosen->kind;
    $model->differenced = $chosen->values;
    $model->offset = $chosen->offset;
    $model->average = $chosen->mean;
    $model->variances = array_map(fn($variant) => $variant->variance, $variants);
    $model->correlations = $chosen->correlations;
    $model->partial = $recursion->partial;
    $model->aic = $aic;
    $model->order = $order;
    $model->coefficients = $recursion->rows[$order];
    $model->sigma2 = $chosen->variance * $recursion->variances[$order];
    $model->residuals = arResiduals($model->differenced, $model->average, $model->coefficients);
}

function fitMethod(string $name, array $values, object $settings): object
{
    $model = (object) compact('name', 'values');
    $season = $settings->season;
    if ($name === 'naive' || $name === 'snaive') {
        $offset = $name === 'naive' ? 1 : $season;
        $model->residuals = [];
        for ($i = $offset; $i < count($values); $i++) {
            $model->residuals[] = $values[$i] - $values[$i - $offset];
        }
    } elseif ($name === 'drift') {
        $model->slope = ($values[count($values) - 1] - $values[0]) / (count($values) - 1);
        $model->residuals = [];
        for ($i = 1; $i < count($values); $i++) {
            $model->residuals[] = $values[$i] - $values[$i - 1] - $model->slope;
        }
    } elseif ($name === 'ar') {
        fitAutoregression($model, $settings);
    } elseif (str_starts_with($name, 'decomp_')) {
        $decomposition = decompose($values, $season);
        $model->seasonal = $name === 'decomp_add' ? $decomposition->add : $decomposition->mult;
        $adjusted = [];
        foreach ($values as $t => $value) {
            $adjusted[] = $name === 'decomp_add' ? $value - $model->seasonal[$t % $season] : $value / $model->seasonal[$t % $season];
        }
        $line = regression($adjusted);
        $model->intercept = $line->intercept;
        $model->slope = $line->slope;
        $model->residuals = [];
        foreach ($values as $t => $value) {
            $model->residuals[] = $value - regressionForecast($model, $t);
        }
    } else {
        $names = $name === 'ses' ? ['alpha'] : ($name === 'holt' ? ['alpha', 'beta'] :
            ($name === 'damped' ? ['alpha', 'beta', 'phi'] : ['alpha', 'beta', 'gamma']));
        $best = null;
        foreach (parameterGrid($names, $settings) as $parameters) {
            $candidate = smooth($name, $values, $season, $parameters);
            $sse = squaredSum($candidate->residuals);
            if ($best === null || $sse < $best->sse) {
                $best = (object) ['states' => $candidate->states, 'residuals' => $candidate->residuals, 'parameters' => $parameters, 'sse' => $sse];
            }
        }
        $model->states = $best->states;
        $model->residuals = $best->residuals;
        $model->parameters = $best->parameters;
    }
    $model->sse = squaredSum($model->residuals);
    $model->residualRmse = sqrt($model->sse / count($model->residuals));
    return $model;
}

function forecast(object $model, int $origin, int $steps, object $settings): array
{
    if ($model->name === 'combo') {
        $result = array_fill(0, $steps, 0.0);
        foreach ($model->members as $member) {
            $values = forecast($member, $origin, $steps, $settings);
            foreach ($values as $k => $value) {
                $result[$k] += $value;
            }
        }
        return array_map(fn($value) => $value / count($model->members), $result);
    }
    if ($model->name === 'ar') {
        return arForecast($model, $origin, $steps, $settings->season);
    }
    if (isset($model->states)) {
        return smoothingForecast($model->name, $model->states[$origin], $origin, $steps, $settings->season, $model->parameters);
    }
    $result = [];
    for ($k = 1; $k <= $steps; $k++) {
        if ($model->name === 'naive') {
            $result[] = $model->values[$origin - 1];
        } elseif ($model->name === 'snaive') {
            $result[] = $model->values[$origin - $settings->season + ($k - 1) % $settings->season];
        } elseif ($model->name === 'drift') {
            $result[] = $model->values[$origin - 1] + $k * (($model->values[$origin - 1] - $model->values[0]) / ($origin - 1));
        } else {
            $result[] = regressionForecast($model, $origin + $k - 1);
        }
    }
    return $result;
}

function crossValidate(object $model, object $settings): object
{
    $squares = $absolute = array_fill(0, $settings->horizon, 0.0);
    $origins = array_fill(0, $settings->horizon, 0);
    for ($origin = $settings->cvStart; $origin < count($model->values); $origin++) {
        $steps = min($settings->horizon, count($model->values) - $origin);
        $values = forecast($model, $origin, $steps, $settings);
        for ($k = 0; $k < $steps; $k++) {
            $error = $model->values[$origin + $k] - $values[$k];
            $squares[$k] += $error * $error;
            $absolute[$k] += abs($error);
            $origins[$k]++;
        }
    }
    $sigma = $mae = [];
    foreach ($squares as $k => $value) {
        $sigma[] = sqrt($value / $origins[$k]);
        $mae[] = $absolute[$k] / $origins[$k];
    }
    $rmse = sqrt(orderedSum(array_slice($squares, 0, $settings->holdout)) / orderedSum(array_slice($origins, 0, $settings->holdout)));
    return (object) compact('origins', 'sigma', 'mae', 'rmse');
}

function modelLines(object $model): array
{
    $name = $model->name;
    $residual = 'rmse ' . formatReal($model->residualRmse) . ' residuals ' . count($model->residuals);
    if ($name === 'naive' || $name === 'snaive') {
        return [$name . ' ' . $residual];
    }
    if ($name === 'drift') {
        return ['drift slope ' . formatReal($model->slope) . ' ' . $residual];
    }
    if ($name === 'ar') {
        $variances = [];
        foreach (DIFFERENCES as $i => $kind) {
            $variances[] = $kind . ' ' . formatReal($model->variances[$i]);
        }
        return ['ar variance ' . implode(' ', $variances),
            'ar difference ' . $model->difference . ' n ' . count($model->differenced) . ' mean ' . formatReal($model->average) .
                ' order ' . $model->order . ' sigma2 ' . formatReal($model->sigma2) . ' ' . $residual,
            'ar aic ' . implode(' ', array_map('formatReal', $model->aic)),
            'ar coefficients ' . ($model->coefficients ? implode(' ', array_map('formatReal', $model->coefficients)) : 'none')];
    }
    if (str_starts_with($name, 'decomp_')) {
        return [$name . ' intercept ' . formatReal($model->intercept) . ' slope ' . formatReal($model->slope) . ' ' . $residual,
            $name . ' seasonal ' . implode(' ', array_map('formatReal', $model->seasonal))];
    }
    $parameters = $model->parameters;
    $state = $model->states[count($model->states) - 1];
    $text = $name . ' alpha ' . formatReal($parameters['alpha']);
    if ($name !== 'ses') {
        $text .= ' beta ' . formatReal($parameters['beta']);
    }
    if ($name === 'damped') {
        $text .= ' phi ' . formatReal($parameters['phi']);
    }
    if (str_starts_with($name, 'hw_')) {
        $text .= ' gamma ' . formatReal($parameters['gamma']);
    }
    $text .= ' ' . $residual . ' level ' . formatReal($state->level);
    if ($name !== 'ses') {
        $text .= ' slope ' . formatReal($state->slope);
    }
    $lines = [$text];
    if (str_starts_with($name, 'hw_')) {
        $rotated = [];
        for ($i = 0; $i < count($state->seasonal); $i++) {
            $rotated[] = $state->seasonal[(count($model->values) + $i) % count($state->seasonal)];
        }
        $lines[] = $name . ' seasonal ' . implode(' ', array_map('formatReal', $rotated));
    }
    return $lines;
}

function predictionRow(string $period, ?int $actual, float $value, float $sigma, float $multiplier, object $settings): object
{
    [$z80, $z95] = $settings->interval;
    return (object) ['period' => $period, 'actual' => $actual, 'forecast' => $value * $multiplier,
        'lo80' => ($value - $z80 * $sigma) * $multiplier, 'hi80' => ($value + $z80 * $sigma) * $multiplier,
        'lo95' => ($value - $z95 * $sigma) * $multiplier, 'hi95' => ($value + $z95 * $sigma) * $multiplier];
}

function assessHoldout(object $model, object $series, object $settings, float $delta): object
{
    $origin = count($series->values) - $settings->holdout;
    $actual = array_slice($series->values, $origin);
    $predictions = forecast($model, $origin, $settings->holdout, $settings);
    $rows = [];
    foreach ($predictions as $i => $value) {
        $rows[] = predictionRow($series->periods[$origin + $i], $actual[$i], $value, $model->cv->sigma[$i], 1.0, $settings);
    }
    $accuracy = accuracy($actual, $predictions, $delta);
    $accuracy->cover80 = $accuracy->cover95 = 0;
    $winkler80 = $winkler95 = 0.0;
    foreach ($rows as $row) {
        $accuracy->cover80 += (int) ($row->lo80 <= $row->actual && $row->actual <= $row->hi80);
        $accuracy->cover95 += (int) ($row->lo95 <= $row->actual && $row->actual <= $row->hi95);
        $winkler80 += winkler($row->actual, $row->lo80, $row->hi80, 10);
        $winkler95 += winkler($row->actual, $row->lo95, $row->hi95, 40);
    }
    $accuracy->winkler80 = $winkler80 / $settings->holdout;
    $accuracy->winkler95 = $winkler95 / $settings->holdout;
    return (object) compact('model', 'rows', 'accuracy');
}

function finalForecast(object $best, array $members, object $series, object $settings): object
{
    $names = $best->model->name === 'combo' ? array_map(fn($model) => $model->name, $members) : [$best->model->name];
    $fitted = array_map(fn($name) => fitMethod($name, $series->cleaned, $settings), $names);
    $model = $best->model->name === 'combo' ? (object) ['name' => 'combo', 'values' => $series->cleaned, 'members' => $fitted] : $fitted[0];
    $cv = crossValidate($model, $settings);
    $predictions = forecast($model, count($series->values), $settings->horizon, $settings);
    $rows = [];
    foreach ($predictions as $k => $value) {
        $period = $series->periods[count($series->values) + $k];
        $kind = $series->events[$period] ?? null;
        $multiplier = $kind === null ? 1.0 : $series->lifts[$kind]->lift;
        $rows[] = predictionRow($period, null, $value, $cv->sigma[$k], $multiplier, $settings);
    }
    return (object) compact('model', 'fitted', 'rows');
}

function inventoryPlan(object $series, object $final, object $settings): array
{
    $onHand = $series->inventory->onHand;
    $leadTime = $series->inventory->leadTime;
    $review = $series->inventory->review;
    $service = $series->inventory->service;
    $span = $leadTime + $review;
    $squaredErrors = 0.0;
    for ($origin = $settings->cvStart; $origin <= count($series->cleaned) - $span; $origin++) {
        $predictions = forecast($final->model, $origin, $span, $settings);
        $error = 0.0;
        for ($k = 0; $k < $span; $k++) {
            $error += $series->cleaned[$origin + $k] - $predictions[$k];
        }
        $squaredErrors += $error * $error;
    }
    $sigma = sqrt($squaredErrors / (count($series->cleaned) - $span - $settings->cvStart + 1));
    $safety = $service * $sigma;
    $reviews = [];
    $lastReview = 1;
    for ($k = 1; $k - 1 + $span <= $settings->horizon; $k += $review) {
        $reviews[$k] = true;
        $lastReview = $k;
    }
    $end = $lastReview - 1 + $span;
    $lines = ['series ' . $series->name . ' method ' . $final->model->name,
        'policy on_hand ' . $onHand . ' lead_time ' . $leadTime . ' review ' . $review .
            ' service ' . formatReal($service) . ' safety_stock ' . formatReal($safety)];
    $receipts = [];
    $stock = $onHand;
    $pending = $orders = $ordered = $shortPeriods = 0;
    $minimum = $totalStock = 0.0;
    for ($k = 1; $k <= $end; $k++) {
        $receipt = $receipts[$k] ?? 0;
        $stock += $receipt;
        $pending -= $receipt;
        $row = $final->rows[$k - 1];
        if (isset($reviews[$k])) {
            $position = $stock + $pending;
            $target = orderedSum(array_map(fn($item) => $item->forecast, array_slice($final->rows, $k - 1, $span))) + $safety;
            $quantity = (int) max(0, ceil($target - $position));
            if ($quantity > 0) {
                $receipts[$k + $leadTime] = $quantity;
                $pending += $quantity;
                $orders++;
                $ordered += $quantity;
            }
            $lines[] = 'review ' . $row->period . ' position ' . formatReal($position) . ' target ' . formatReal($target) . ' order ' . $quantity;
        }
        $stock -= $row->forecast;
        $status = $stock < 0 ? 'short' : ($stock < $safety ? 'low' : 'ok');
        if ($status === 'short') {
            $shortPeriods++;
        }
        if ($k === 1 || $stock < $minimum) {
            $minimum = $stock;
        }
        $totalStock += $stock;
        $lines[] = 'period ' . $row->period . ' demand ' . formatReal($row->forecast) . ' receipt ' . $receipt .
            ' on_hand ' . formatReal($stock) . ' status ' . $status;
    }
    $lines[] = 'summary orders ' . $orders . ' ordered ' . $ordered . ' short_periods ' . $shortPeriods .
        ' lowest ' . formatReal($minimum) . ' average ' . formatReal($totalStock / $end);
    return $lines;
}

function yearlyTotals(object $series, array $futureRows): array
{
    $years = [];
    foreach ($series->values as $t => $value) {
        $year = substr($series->periods[$t], 0, 4);
        if (!isset($years[$year])) {
            $years[$year] = (object) ['year' => $year, 'actualMonths' => 0, 'actual' => 0.0, 'forecastMonths' => 0, 'forecast' => 0.0];
        }
        $years[$year]->actualMonths++;
        $years[$year]->actual += $value;
    }
    foreach ($futureRows as $row) {
        $year = substr($row->period, 0, 4);
        if (!isset($years[$year])) {
            $years[$year] = (object) ['year' => $year, 'actualMonths' => 0, 'actual' => 0.0, 'forecastMonths' => 0, 'forecast' => 0.0];
        }
        $years[$year]->forecastMonths++;
        $years[$year]->forecast += $row->forecast;
    }
    ksort($years, SORT_STRING);
    $lines = [];
    $previous = null;
    foreach ($years as $entry) {
        $entry->total = $entry->actual + $entry->forecast;
        $entry->months = $entry->actualMonths + $entry->forecastMonths;
        $growth = $previous !== null && $entry->months === 12 && $previous->months === 12 ?
            formatReal(100.0 * ($entry->total - $previous->total) / $previous->total) : 'NA';
        $lines[] = 'year ' . $entry->year . ' actual_months ' . $entry->actualMonths . ' actual ' . formatReal($entry->actual) .
            ' forecast_months ' . $entry->forecastMonths . ' forecast ' . formatReal($entry->forecast) .
            ' total ' . formatReal($entry->total) . ' growth ' . $growth;
        $previous = $entry;
    }
    return $lines;
}

function residualDiagnostics(object $model): string
{
    $count = count($model->residuals);
    $average = mean($model->residuals);
    $second = $third = $fourth = $successive = 0.0;
    foreach ($model->residuals as $i => $value) {
        $centered = $value - $average;
        $second += $centered * $centered;
        $third += $centered * $centered * $centered;
        $fourth += $centered * $centered * $centered * $centered;
        if ($i > 0) {
            $difference = $value - $model->residuals[$i - 1];
            $successive += $difference * $difference;
        }
    }
    $m2 = $second / $count;
    $m3 = $third / $count;
    $m4 = $fourth / $count;
    $sd = sqrt($second / ($count - 1));
    $dw = $successive / $model->sse;
    $skewness = $m3 / ($m2 * sqrt($m2));
    $kurtosis = $m4 / ($m2 * $m2) - 3.0;
    $jb = $count / 6.0 * ($skewness * $skewness + $kurtosis * $kurtosis / 4.0);
    return 'residuals ' . $model->name . ' n ' . $count . ' mean ' . formatReal($average) . ' sd ' . formatReal($sd) .
        ' dw ' . formatReal($dw) . ' skewness ' . formatReal($skewness) . ' kurtosis ' . formatReal($kurtosis) . ' jb ' . formatReal($jb);
}

function correlationBar(float $correlation, float $band): string
{
    $bar = array_fill(0, 41, ' ');
    $boundary = (int) floor($band * 20 + 0.5);
    $length = (int) floor(abs($correlation) * 20 + 0.5);
    $bar[20 - $boundary] = ':';
    $bar[20 + $boundary] = ':';
    $bar[20] = '|';
    if ($correlation > 0) {
        for ($i = 21; $i <= 20 + $length; $i++) {
            $bar[$i] = '#';
        }
    }
    if ($correlation < 0) {
        for ($i = 20 - $length; $i <= 19; $i++) {
            $bar[$i] = '#';
        }
    }
    return implode('', $bar);
}

function correlogram(object $series, array $methods, object $settings): array
{
    $ar = $methods[count($methods) - 1];
    $band = 2.0 / sqrt(count($ar->differenced));
    $lines = ['series ' . $series->name . ' difference ' . $ar->difference . ' n ' . count($ar->differenced) . ' band ' . formatReal($band)];
    foreach (['acf' => $ar->correlations, 'pacf' => $ar->partial] as $name => $values) {
        for ($k = 1; $k <= $settings->maxLag; $k++) {
            $value = $values[$k];
            $lines[] = $name . ' ' . str_pad((string) $k, 2, ' ', STR_PAD_LEFT) . ' ' . str_pad(formatReal($value), 7, ' ', STR_PAD_LEFT) .
                ' [' . correlationBar($value, $band) . ']' . (abs($value) > $band ? ' *' : '');
        }
    }
    foreach ($methods as $method) {
        $lines[] = residualDiagnostics($method);
        $tests = [];
        foreach (ljungBox($method->residuals, $settings->ljungBox) as $test) {
            $tests[] = 'lag ' . $test->lag . ' q ' . formatReal($test->q) . ' p ' . formatReal($test->p);
        }
        $lines[] = 'ljung_box ' . $method->name . ' ' . implode(' ', $tests);
    }
    return $lines;
}

function forecastChart(object $series, object $best, object $final): array
{
    $rows = array_merge($best->rows, $final->rows);
    $low = $rows[0]->lo95;
    $high = $rows[0]->hi95;
    foreach ($rows as $row) {
        $low = min($low, $row->lo95);
        $high = max($high, $row->hi95);
        if ($row->actual !== null) {
            $low = min($low, $row->actual);
            $high = max($high, $row->actual);
        }
    }
    $column = fn($value) => (int) floor(($value - $low) / ($high - $low) * 60 + 0.5);
    $lines = ['chart ' . $series->name . ' method ' . $best->model->name, 'scale low ' . formatReal($low) . ' high ' . formatReal($high)];
    foreach ($rows as $row) {
        $chart = array_fill(0, 61, ' ');
        for ($i = $column($row->lo95); $i <= $column($row->hi95); $i++) {
            $chart[$i] = '-';
        }
        for ($i = $column($row->lo80); $i <= $column($row->hi80); $i++) {
            $chart[$i] = '=';
        }
        $chart[$column($row->forecast)] = 'o';
        if ($row->actual !== null) {
            $chart[$column($row->actual)] = '*';
        }
        $lines[] = $row->period . ' |' . implode('', $chart) . '|';
    }
    $peak = 0.0;
    foreach ($series->decomposition->mult as $seasonal) {
        $peak = max($peak, abs($seasonal - 1.0));
    }
    $lines[] = 'profile peak ' . formatReal($peak);
    foreach ($series->decomposition->mult as $j => $seasonal) {
        $chart = array_fill(0, 61, ' ');
        $chart[30] = '|';
        $length = (int) floor(abs($seasonal - 1.0) / $peak * 30 + 0.5);
        if ($seasonal > 1.0) {
            for ($i = 31; $i <= 30 + $length; $i++) {
                $chart[$i] = '#';
            }
        }
        if ($seasonal < 1.0) {
            for ($i = 30 - $length; $i <= 29; $i++) {
                $chart[$i] = '#';
            }
        }
        $lines[] = 'season ' . str_pad((string) ($j + 1), 2, ' ', STR_PAD_LEFT) . ' ' . formatReal($seasonal) . ' [' . implode('', $chart) . ']';
    }
    return $lines;
}

function decompositionLines(object $series, object $settings): array
{
    $lines = [];
    $d = $series->decomposition;
    $valueText = fn($value) => $value === null ? 'NA' : formatReal($value);
    foreach ($series->values as $t => $value) {
        $flag = $series->pastEvents[$t] ?? (isset($series->missing[$t]) ? 'missing' : (isset($series->outliers[$t]) ? 'outlier' : 'ok'));
        $j = $t % $settings->season;
        $lines[] = implode(',', [$series->name, $series->periods[$t], formatReal($value), formatReal($series->cleaned[$t]), $valueText($d->trend[$t]),
            formatReal($d->add[$j]), $valueText($d->residualAdd[$t]), formatReal($d->mult[$j]), $valueText($d->residualMult[$t]), $flag]);
    }
    return $lines;
}

function fittedModelLines(object $series, array $methods, array $members, object $best, object $final, object $settings): array
{
    $lines = ['series ' . $series->name, 'data observations ' . count($series->values) . ' train ' . (count($series->values) - $settings->holdout) .
        ' holdout ' . $settings->holdout . ' missing ' . count($series->missing) . ' outliers ' . count($series->outliers) . ' events ' . count($series->pastEvents)];
    foreach ($series->lifts as $kind => $entry) {
        $lines[] = 'event ' . $kind . ' occurrences ' . $entry->count . ' lift ' . formatReal($entry->lift);
    }
    foreach ($series->outliers as $t => $score) {
        $lines[] = 'outlier ' . $series->periods[$t] . ' value ' . formatReal($series->values[$t]) .
            ' expected ' . formatReal($series->cleaned[$t]) . ' score ' . formatReal($score);
    }
    $lines[] = 'strength trend ' . formatReal($series->strengthTrend) . ' seasonal ' . formatReal($series->strengthSeasonal);
    foreach ($methods as $method) {
        array_push($lines, ...modelLines($method));
    }
    $lines[] = 'combo members ' . implode(' ', array_map(fn($model) => $model->name, $members));
    $lines[] = 'best ' . $best->model->name . ' rmse ' . formatReal($best->accuracy->rmse);
    foreach ($final->fitted as $method) {
        foreach (modelLines($method) as $line) {
            $lines[] = 'final ' . $line;
        }
    }
    return $lines;
}

function forecastLine(object $series, string $stage, string $name, object $row): string
{
    return implode(',', [$series->name, $stage, $name, $row->period, $row->actual === null ? 'NA' : $row->actual,
        formatReal($row->forecast), formatReal($row->lo80), formatReal($row->hi80), formatReal($row->lo95), formatReal($row->hi95)]);
}

function appendReports(object $reports, object $series, array $methods, array $members, array $assessments,
    object $best, object $final, object $settings): void
{
    array_push($reports->decomposition, ...decompositionLines($series, $settings));
    array_push($reports->models, ...fittedModelLines($series, $methods, $members, $best, $final, $settings));
    foreach ($assessments as $assessment) {
        $model = $assessment->model;
        $a = $assessment->accuracy;
        foreach ($assessment->rows as $row) {
            $reports->forecasts[] = forecastLine($series, 'holdout', $model->name, $row);
        }
        $reports->accuracy[] = implode(',', [$series->name, $model->name, formatReal($a->me), formatReal($a->mae), formatReal($a->rmse),
            formatReal($a->mape), formatReal($a->smape), formatReal($a->mase), formatReal($a->fva), formatReal($model->cv->rmse),
            $a->cover80, $a->cover95, formatReal($a->winkler80), formatReal($a->winkler95), $a->rank]);
        for ($k = 0; $k < $settings->horizon; $k++) {
            $reports->cv[] = implode(',', [$series->name, $model->name, $k + 1, $model->cv->origins[$k],
                formatReal($model->cv->mae[$k]), formatReal($model->cv->sigma[$k])]);
        }
    }
    foreach ($final->rows as $row) {
        $reports->forecasts[] = forecastLine($series, 'future', $best->model->name, $row);
    }
    array_push($reports->correlogram, ...correlogram($series, $methods, $settings));
    array_push($reports->chart, ...forecastChart($series, $best, $final));
    array_push($reports->plan, ...inventoryPlan($series, $final, $settings));
    array_push($reports->plan, ...yearlyTotals($series, $final->rows));
}

$input = readInput();
$settings = $input->settings;
$reports = (object) [
    'decomposition' => ['series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag'],
    'models' => [], 'forecasts' => ['series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95'],
    'accuracy' => ['series,method,me,mae,rmse,mape,smape,mase,fva,cv_rmse,cover80,cover95,winkler80,winkler95,rank'],
    'cv' => ['series,method,step,origins,mae,rmse'], 'correlogram' => [], 'chart' => [], 'plan' => []
];
foreach ($input->series as $inputSeries) {
    $series = prepareSeries($inputSeries, $settings);
    $training = array_slice($series->cleaned, 0, count($series->values) - $settings->holdout);
    $methods = array_map(fn($name) => fitMethod($name, $training, $settings), METHODS);
    foreach ($methods as $method) {
        $method->cv = crossValidate($method, $settings);
    }
    $selected = array_slice(rankedIndices(array_map(fn($model) => $model->cv->rmse, $methods)), 0, $settings->combo);
    sort($selected, SORT_NUMERIC);
    $members = array_map(fn($index) => $methods[$index], $selected);
    $combo = (object) ['name' => 'combo', 'values' => $training, 'members' => $members];
    $combo->cv = crossValidate($combo, $settings);
    $delta = seasonalScale($training, $settings->season);
    $assessments = [];
    foreach (array_merge($methods, [$combo]) as $model) {
        $assessments[] = assessHoldout($model, $series, $settings, $delta);
    }
    foreach ($assessments as $assessment) {
        $assessment->accuracy->fva = 100.0 * ($assessments[0]->accuracy->mae - $assessment->accuracy->mae) / $assessments[0]->accuracy->mae;
    }
    $ranking = rankedIndices(array_map(fn($assessment) => $assessment->accuracy->rmse, $assessments));
    foreach ($ranking as $index => $position) {
        $assessments[$position]->accuracy->rank = $index + 1;
    }
    $best = $assessments[$ranking[0]];
    $final = finalForecast($best, $members, $series, $settings);
    appendReports($reports, $series, $methods, $members, $assessments, $best, $final, $settings);
}
foreach (['decomposition' => 'csv', 'models' => 'txt', 'forecasts' => 'csv', 'accuracy' => 'csv',
    'cv' => 'csv', 'correlogram' => 'txt', 'chart' => 'txt', 'plan' => 'txt'] as $name => $extension) {
    writeLines($name . '.' . $extension, $reports->$name);
}
