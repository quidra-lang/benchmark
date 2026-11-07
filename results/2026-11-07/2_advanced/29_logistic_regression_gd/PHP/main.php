<?php

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/logistic.php';
require_once __DIR__ . '/optimizers.php';
require_once __DIR__ . '/softmax.php';
require_once __DIR__ . '/metrics.php';

function sumValues(array $values, ?callable $term = null): float
{
    $total = 0.0;
    foreach ($values as $index => $value) {
        $total += $term === null ? $value : $term($value, $index);
    }
    return $total;
}

function vectorLength(array $vector): float
{
    return sqrt(sumValues($vector, fn($value) => $value * $value));
}

function prepareData(): object
{
    $data = readInputs();
    $data->features = expandedFeatures($data->names, $data->settings->degree);
    $data->classes = max($data->train->labels) + 1;
    foreach ([$data->train, $data->test] as $rows) {
        $rows->count = count($rows->ids);
        $rows->expanded = array_map(fn($values) => expand($values, $data->features), $rows->base);
        $rows->targets = array_map(fn($label) => (int) ($label === $data->settings->positive), $rows->labels);
        $rows->positive = array_sum($rows->targets);
        $rows->classCounts = array_fill(0, $data->classes, 0);
        foreach ($rows->labels as $label) {
            $rows->classCounts[$label]++;
        }
    }
    $data->statistics = featureStatistics($data->train->expanded);
    $data->train->vectors = standardize($data->train->expanded, $data->statistics);
    $data->test->vectors = standardize($data->test->expanded, $data->statistics);
    $data->baseMean = array_slice($data->statistics->means, 0, count($data->names));
    $data->bounds = [];
    foreach ($data->names as $feature => $_) {
        $values = array_map(fn($row) => $row[$feature], $data->train->base);
        $data->bounds[] = (object) ['low' => min($values), 'high' => max($values)];
    }
    return $data;
}

function inverse(array $matrix): array
{
    $factor = cholesky($matrix);
    $size = count($matrix);
    $result = array_fill(0, $size, array_fill(0, $size, 0.0));
    for ($column = 0; $column < $size; $column++) {
        $right = array_fill(0, $size, 0.0);
        $right[$column] = 1.0;
        $solution = solveFactor($factor, $right);
        foreach ($solution as $row => $value) {
            $result[$row][$column] = $value;
        }
    }
    return $result;
}

function influence(array $weights, array $vectors, array $targets, float $lambda): object
{
    $evaluation = logisticEvaluate($weights, $vectors, $targets, $lambda);
    $matrix = inverse(logisticHessian($weights, $vectors, $lambda));
    $rows = [];
    foreach ($vectors as $row => $vector) {
        $probability = $evaluation->probabilities[$row];
        $variance = $probability * (1.0 - $probability);
        $quadratic = 0.0;
        for ($first = 0; $first < count($weights); $first++) {
            for ($second = 0; $second < count($weights); $second++) {
                $quadratic += $vector[$first] * $matrix[$first][$second] * $vector[$second];
            }
        }
        $leverage = $variance * $quadratic / count($vectors);
        $pearson = ($targets[$row] - $probability) / sqrt($variance);
        $residual = $pearson / sqrt(1.0 - $leverage);
        $cook = $pearson * $pearson * $leverage / (count($weights) * ((1.0 - $leverage) * (1.0 - $leverage)));
        $rows[] = (object) ['index' => $row, 'probability' => $probability, 'leverage' => $leverage, 'residual' => $residual, 'cook' => $cook];
    }
    $edf = sumValues($rows, fn($row) => $row->leverage);
    $deviance = 2.0 * count($vectors) * $evaluation->loss;
    return (object) ['matrix' => $matrix, 'rows' => $rows, 'edf' => $edf, 'deviance' => $deviance,
        'loss' => $evaluation->loss, 'aic' => $deviance + 2.0 * $edf, 'bic' => $deviance + log(count($vectors)) * $edf];
}

function originalWeights(array $weights, object $stats): array
{
    $result = $weights;
    $shift = 0.0;
    for ($component = 1; $component < count($weights); $component++) {
        $result[$component] = $weights[$component] / $stats->deviations[$component - 1];
        $shift += $result[$component] * $stats->means[$component - 1];
    }
    $result[0] = $weights[0] - $shift;
    return $result;
}

function featureCorrelations(object $data): object
{
    $matrix = [];
    foreach ($data->features as $first => $_) {
        $row = [];
        foreach ($data->features as $second => $_) {
            $row[] = sumValues($data->train->vectors, fn($vector) => $vector[$first + 1] * $vector[$second + 1]) / ($data->train->count - 1);
        }
        $matrix[] = $row;
    }
    $inverted = inverse($matrix);
    $vif = [];
    foreach ($inverted as $index => $row) {
        $vif[] = $row[$index];
    }
    return (object) compact('matrix', 'vif');
}

function crossValidate(object $data, int $width, float $lambda): object
{
    $losses = $probabilities = array_fill(0, $data->train->count, 0.0);
    $foldLosses = [];
    $errors = 0;
    for ($fold = 0; $fold < 5; $fold++) {
        $training = $validation = [];
        for ($row = 0; $row < $data->train->count; $row++) {
            if ($row % 5 === $fold) {
                $validation[] = $row;
            } else {
                $training[] = $row;
            }
        }
        $expanded = array_map(fn($row) => $data->train->expanded[$row], $training);
        $stats = featureStatistics($expanded, $width);
        $vectors = standardize($expanded, $stats);
        $targets = array_map(fn($row) => $data->train->targets[$row], $training);
        $fitted = newton($vectors, $targets, $lambda);
        $foldLoss = 0.0;
        foreach ($validation as $row) {
            $vector = standardizeOne($data->train->expanded[$row], $stats);
            $score = score($fitted->weights, $vector);
            $losses[$row] = logisticLoss($score, $data->train->targets[$row]);
            $probabilities[$row] = sigmoid($score);
            $foldLoss += $losses[$row];
            if ((int) ($probabilities[$row] >= $data->settings->threshold) !== $data->train->targets[$row]) {
                $errors++;
            }
        }
        $foldLosses[] = $foldLoss / count($validation);
    }
    return (object) ['lambda' => $lambda, 'foldLosses' => $foldLosses, 'loss' => sumValues($losses) / $data->train->count,
        'errors' => $errors, 'probabilities' => $probabilities];
}

function selectLambda(object $data): object
{
    $candidates = array_map(fn($lambda) => crossValidate($data, count($data->features), $lambda), $data->settings->lambdas);
    $selected = $candidates[0];
    foreach ($candidates as $candidate) {
        if ($candidate->loss <= $selected->loss) {
            $selected = $candidate;
        }
    }
    $mean = sumValues($selected->foldLosses) / 5.0;
    $se = sqrt(sumValues($selected->foldLosses, fn($value) => ($value - $mean) * ($value - $mean)) / 4.0) / sqrt(5.0);
    $oneSE = $candidates[0]->lambda;
    foreach ($candidates as $candidate) {
        if ($candidate->loss <= $selected->loss + $se) {
            $oneSE = $candidate->lambda;
        }
    }
    return (object) ['candidates' => $candidates, 'selected' => $selected, 'se' => $se, 'oneSE' => $oneSE,
        'confusion' => confusion($selected->probabilities, $data->train->targets, $data->settings->threshold),
        'auc' => auc($selected->probabilities, $data->train->targets)];
}

function fitSummary(array $weights, array $training, array $targets, array $testing, array $testTargets, float $lambda, float $threshold): object
{
    $train = logisticEvaluate($weights, $training, $targets, $lambda);
    $test = logisticEvaluate($weights, $testing, $testTargets);
    return (object) ['weights' => $weights, 'train' => $train, 'test' => $test, 'norm' => vectorLength(array_slice($weights, 1)),
        'trainCorrect' => confusion($train->probabilities, $targets, $threshold)->correct,
        'testCorrect' => confusion($test->probabilities, $testTargets, $threshold)->correct, 'auc' => auc($test->probabilities, $testTargets)];
}

function lambdaPath(object $data): array
{
    $results = [];
    foreach ($data->settings->lambdas as $lambda) {
        $fitted = newton($data->train->vectors, $data->train->targets, $lambda);
        $result = fitSummary($fitted->weights, $data->train->vectors, $data->train->targets, $data->test->vectors,
            $data->test->targets, $lambda, $data->settings->threshold);
        $result->lambda = $lambda;
        $results[] = $result;
    }
    return $results;
}

function degreeComparison(object $data, float $lambda): array
{
    $results = [];
    for ($degree = 1; $degree <= $data->settings->degree; $degree++) {
        $width = count(array_filter($data->features, fn($feature) => $feature->degree <= $degree));
        $training = array_map(fn($vector) => array_slice($vector, 0, $width + 1), $data->train->vectors);
        $testing = array_map(fn($vector) => array_slice($vector, 0, $width + 1), $data->test->vectors);
        $fitted = newton($training, $data->train->targets, $lambda);
        $result = fitSummary($fitted->weights, $training, $data->train->targets, $testing, $data->test->targets, $lambda, $data->settings->threshold);
        $result->degree = $degree;
        $result->width = $width;
        $result->cv = crossValidate($data, $width, $lambda)->loss;
        $result->influence = influence($fitted->weights, $training, $data->train->targets, $lambda);
        $results[] = $result;
    }
    return $results;
}

function learningCurve(object $data, float $lambda): array
{
    $results = [];
    for ($step = 1; $step <= 4; $step++) {
        $size = intdiv($step * $data->train->count, 4);
        $expanded = array_slice($data->train->expanded, 0, $size);
        $stats = featureStatistics($expanded);
        $training = standardize($expanded, $stats);
        $testing = standardize($data->test->expanded, $stats);
        $targets = array_slice($data->train->targets, 0, $size);
        $fitted = newton($training, $targets, $lambda);
        $result = fitSummary($fitted->weights, $training, $targets, $testing, $data->test->targets, $lambda, $data->settings->threshold);
        $result->size = $size;
        $results[] = $result;
    }
    return $results;
}

function trainModels(object $data, float $lambda): array
{
    $models = [gradientDescent($data->train->vectors, $data->train->targets, $lambda, ...$data->settings->gd),
        stochasticDescent($data->train->vectors, $data->train->targets, $lambda, ...$data->settings->sgd),
        newton($data->train->vectors, $data->train->targets, $lambda)];
    foreach (['gd', 'sgd', 'newton'] as $index => $name) {
        $models[$index]->name = $name;
    }
    return $models;
}

function calibration(array $probabilities, array $targets): object
{
    $bins = [];
    for ($i = 0; $i < 10; $i++) {
        $bins[] = (object) ['count' => 0, 'total' => 0.0, 'positives' => 0];
    }
    foreach ($probabilities as $index => $probability) {
        $bin = $bins[min(9, (int) floor($probability * 10))];
        $bin->count++;
        $bin->total += $probability;
        $bin->positives += $targets[$index];
    }
    $ece = $mce = $hl = 0.0;
    $groups = 0;
    foreach ($bins as $bin) {
        if ($bin->count === 0) {
            continue;
        }
        $groups++;
        $ece += abs($bin->total - $bin->positives);
        $mce = max($mce, abs($bin->total / $bin->count - $bin->positives / $bin->count));
        $difference = $bin->positives - $bin->total;
        $hl += $difference * $difference / ($bin->total * (1.0 - $bin->total / $bin->count));
    }
    $ece /= count($probabilities);
    return (object) compact('bins', 'ece', 'mce', 'hl', 'groups');
}

function binaryAnalysis(object $data, object $fitted, float $lambda): object
{
    $summary = fitSummary($fitted->weights, $data->train->vectors, $data->train->targets,
        $data->test->vectors, $data->test->targets, $lambda, $data->settings->threshold);
    foreach (get_object_vars($summary) as $key => $value) {
        $fitted->$key = $value;
    }
    $probabilities = $summary->test->probabilities;
    $table = confusion($probabilities, $data->test->targets, $data->settings->threshold);
    $points = rocPoints($probabilities, $data->test->targets);
    $positive = $data->test->positive;
    $negative = $data->test->count - $positive;
    [$fpCost, $fnCost] = $data->settings->cost;
    $cost = fn($point) => $fpCost * $point->fp + $fnCost * ($positive - $point->tp);
    $youdenValue = fn($point) => $point->tp * $negative - $point->fp * $positive;
    $youden = $bestF1 = $minCost = $points[0];
    $averagePrecision = 0.0;
    $previousTP = 0;
    foreach ($points as $point) {
        $averagePrecision += ($point->tp - $previousTP) * $point->tp / ($point->tp + $point->fp);
        $previousTP = $point->tp;
        if ($youdenValue($point) > $youdenValue($youden)) {
            $youden = $point;
        }
        if (compareFractions([2 * $point->tp, $positive + $point->tp + $point->fp],
            [2 * $bestF1->tp, $positive + $bestF1->tp + $bestF1->fp]) > 0) {
            $bestF1 = $point;
        }
        if ($cost($point) < $cost($minCost)) {
            $minCost = $point;
        }
    }
    $order = range(0, count($probabilities) - 1);
    usort($order, fn($a, $b) => ($probabilities[$b] <=> $probabilities[$a]) ?: ($a <=> $b));
    $gains = [];
    for ($decile = 1; $decile <= 10; $decile++) {
        $size = intdiv($decile * $data->test->count, 10);
        $hits = 0;
        foreach (array_slice($order, 0, $size) as $row) {
            $hits += $data->test->targets[$row];
        }
        $gains[] = (object) compact('decile', 'size', 'hits');
    }
    $brier = sumValues($probabilities, fn($p, $row) => ($p - $data->test->targets[$row]) * ($p - $data->test->targets[$row])) / $data->test->count;
    $fitted->confusion = $table;
    $fitted->points = $points;
    $fitted->youden = $youden;
    $fitted->bestF1 = $bestF1;
    $fitted->minCost = (object) ['threshold' => $minCost->threshold, 'tp' => $minCost->tp, 'fp' => $minCost->fp, 'cost' => $cost($minCost)];
    $fitted->averagePrecision = $averagePrecision / $positive;
    $fitted->brier = $brier;
    $fitted->calibration = calibration($probabilities, $data->test->targets);
    $fitted->gains = $gains;
    return $fitted;
}

function multiclassAnalysis(object $data, object $fitted, object $binary): object
{
    $evaluation = softmaxEvaluate($fitted->weights, $data->test->vectors, $data->test->labels);
    $table = array_fill(0, $data->classes, array_fill(0, $data->classes, 0));
    $bins = [];
    for ($i = 0; $i < 10; $i++) {
        $bins[] = (object) ['count' => 0, 'total' => 0.0, 'hits' => 0];
    }
    $brier = 0.0;
    $correct = 0;
    foreach ($evaluation->rows as $index => $row) {
        $table[$data->test->labels[$index]][$row->predicted]++;
        $hit = (int) ($row->predicted === $data->test->labels[$index]);
        $correct += $hit;
        $squared = 0.0;
        foreach ($row->probabilities as $label => $probability) {
            $difference = $probability - (int) ($label === $data->test->labels[$index]);
            $squared += $difference * $difference;
        }
        $brier += $squared;
        $confidence = $row->probabilities[$row->predicted];
        $bin = $bins[min(9, (int) floor($confidence * 10))];
        $bin->count++;
        $bin->total += $confidence;
        $bin->hits += $hit;
    }
    $rowTotals = array_map('array_sum', $table);
    $columnTotals = [];
    $expected = 0;
    for ($label = 0; $label < $data->classes; $label++) {
        $columnTotals[] = array_sum(array_column($table, $label));
        $expected += $rowTotals[$label] * $columnTotals[$label];
    }
    $classAUC = [];
    for ($label = 0; $label < $data->classes; $label++) {
        $scores = array_map(fn($row) => $row->probabilities[$label], $evaluation->rows);
        $targets = array_map(fn($value) => (int) ($value === $label), $data->test->labels);
        $classAUC[] = auc($scores, $targets);
    }
    $probabilities = array_map(fn($row) => $row->probabilities[$data->settings->positive], $evaluation->rows);
    $binaryConfusion = confusion($probabilities, $data->test->targets, $data->settings->threshold);
    $binaryLoss = sumValues($probabilities, fn($p, $index) => -log($data->test->targets[$index] === 1 ? $p : 1.0 - $p)) / $data->test->count;
    $agreement = 0;
    foreach ($binaryConfusion->predictions as $index => $prediction) {
        $agreement += (int) ($prediction === $binary->confusion->predictions[$index]);
    }
    $ece = sumValues($bins, fn($bin) => $bin->count === 0 ? 0.0 : abs($bin->total - $bin->hits)) / $data->test->count;
    return (object) ['weights' => $fitted->weights, 'checkpoints' => $fitted->checkpoints, 'rows' => $evaluation->rows, 'loss' => $evaluation->loss,
        'table' => $table, 'rowTotals' => $rowTotals, 'columnTotals' => $columnTotals, 'classAUC' => $classAUC, 'correct' => $correct,
        'brier' => $brier / $data->test->count, 'kappa' => [$data->test->count * $correct - $expected, $data->test->count ** 2 - $expected],
        'binaryAUC' => auc($probabilities, $data->test->targets), 'binaryConfusion' => $binaryConfusion, 'binaryLoss' => $binaryLoss,
        'agreement' => $agreement, 'bins' => $bins, 'ece' => $ece];
}

function bootstrap(object $data, array $probabilities): object
{
    [$count, $seed] = $data->settings->bootstrap;
    $generator = new Minstd($seed);
    $results = [];
    for ($replicate = 0; $replicate < $count; $replicate++) {
        $selected = [];
        for ($draw = 0; $draw < $data->test->count; $draw++) {
            $selected[] = $generator->draw() % $data->test->count;
        }
        $scores = array_map(fn($row) => $probabilities[$row], $selected);
        $targets = array_map(fn($row) => $data->test->targets[$row], $selected);
        $value = auc($scores, $targets);
        $results[] = (object) ['fraction' => $value, 'value' => $value[0] / $value[1]];
    }
    $mean = sumValues($results, fn($item) => $item->value) / $count;
    $sd = sqrt(sumValues($results, fn($item) => ($item->value - $mean) * ($item->value - $mean)) / ($count - 1));
    $sorted = $results;
    usort($sorted, fn($a, $b) => $a->value <=> $b->value);
    return (object) ['mean' => $mean, 'sd' => $sd, 'lower' => $sorted[intdiv($count, 40)]->fraction,
        'upper' => $sorted[$count - intdiv($count, 40) - 1]->fraction];
}

function slope(object $data, array $weights, array $base, int $feature): float
{
    $total = 0.0;
    foreach ($data->features as $index => $expanded) {
        $count = 0;
        foreach ($expanded->tuple as $component) {
            if ($component === $feature) {
                $count++;
            }
        }
        if ($count === 0) {
            continue;
        }
        $product = 1.0;
        $removed = false;
        foreach ($expanded->tuple as $component) {
            if ($component === $feature && !$removed) {
                $removed = true;
            } else {
                $product *= $base[$component];
            }
        }
        $total += $weights[$index + 1] * ($count * $product);
    }
    return $total;
}

function newtonDiagnostics(object $data, object $model, float $lambda, object $measures): object
{
    $positiveRate = $data->train->positive / $data->train->count;
    $nullLoss = -($positiveRate * log($positiveRate) + (1.0 - $positiveRate) * log(1.0 - $positiveRate));
    $sorted = $measures->rows;
    usort($sorted, fn($a, $b) => ($a->probability <=> $b->probability) ?: ($a->index <=> $b->index));
    $groups = [];
    $hl = 0.0;
    for ($group = 1; $group <= 10; $group++) {
        $first = intdiv(($group - 1) * $data->train->count, 10);
        $last = intdiv($group * $data->train->count, 10);
        $rows = array_slice($sorted, $first, $last - $first);
        $expected = sumValues($rows, fn($row) => $row->probability);
        $observed = (int) sumValues($rows, fn($row) => $data->train->targets[$row->index]);
        $difference = $observed - $expected;
        $hl += $difference * $difference / ($expected * (1.0 - $expected / count($rows)));
        $groups[] = (object) ['group' => $group, 'size' => count($rows), 'observed' => $observed, 'expected' => $expected];
    }
    $iterations = [];
    foreach ($model->steps as $index => $step) {
        $objective = logisticEvaluate($model->checkpoints[$index]->weights, $data->train->vectors, $data->train->targets, $lambda)->objective;
        $decrease = sumValues($step->gradient, fn($value, $component) => $value * $step->delta[$component]) / 2.0;
        $iterations[] = (object) ['iteration' => $index + 1, 'objective' => $objective,
            'gradient' => vectorLength($step->gradient), 'step' => vectorLength($step->delta), 'decrease' => $decrease];
    }
    $original = originalWeights($model->weights, $data->statistics);
    $meanVector = standardizeOne(expand($data->baseMean, $data->features), $data->statistics);
    $meanProbability = sigmoid(score($model->weights, $meanVector));
    $marginals = [];
    foreach ($data->names as $feature => $name) {
        $average = sumValues($measures->rows, fn($row) => $row->probability * (1.0 - $row->probability) *
            slope($data, $original, $data->train->base[$row->index], $feature)) / $data->train->count;
        $atMean = $meanProbability * (1.0 - $meanProbability) * slope($data, $original, $data->baseMean, $feature);
        $marginals[] = (object) compact('name', 'average', 'atMean');
    }
    $thresholds = [];
    for ($digit = 1; $digit <= 9; $digit++) {
        $cut = confusion($model->test->probabilities, $data->test->targets, $digit / 10.0);
        $cut->digit = $digit;
        $thresholds[] = $cut;
    }
    $errors = [];
    foreach ($model->confusion->predictions as $index => $prediction) {
        if ($prediction !== $data->test->targets[$index]) {
            $errors[] = $index;
        }
    }
    usort($errors, fn($a, $b) => (abs($model->test->probabilities[$b] - $data->settings->threshold) <=>
        abs($model->test->probabilities[$a] - $data->settings->threshold)) ?: ($a <=> $b));
    $errors = array_slice($errors, 0, 5);
    $cooks = $measures->rows;
    usort($cooks, fn($a, $b) => ($b->cook <=> $a->cook) ?: ($a->index <=> $b->index));
    $largeResiduals = count(array_filter($measures->rows, fn($row) => abs($row->residual) > 2.0));
    return (object) ['nullLoss' => $nullLoss, 'mcfadden' => 1.0 - $measures->loss / $nullLoss,
        'groups' => $groups, 'hl' => $hl, 'iterations' => $iterations, 'marginals' => $marginals, 'thresholds' => $thresholds,
        'errors' => $errors, 'bootstrap' => bootstrap($data, $model->test->probabilities), 'cooks' => array_slice($cooks, 0, 5),
        'largeResiduals' => $largeResiduals];
}

function permutationImportance(object $data, object $binary, object $multiclass): array
{
    [$repetitions, $seed] = $data->settings->permutation;
    $generator = new Minstd($seed);
    $results = [];
    foreach ($data->names as $feature => $name) {
        $losses = 0.0;
        $numerators = $correct = 0;
        for ($repeat = 0; $repeat < $repetitions; $repeat++) {
            $order = range(0, $data->test->count - 1);
            shuffleWithGenerator($order, $generator);
            $base = $data->test->base;
            foreach ($base as $index => $row) {
                $base[$index][$feature] = $data->test->base[$order[$index]][$feature];
            }
            $expanded = array_map(fn($values) => expand($values, $data->features), $base);
            $vectors = standardize($expanded, $data->statistics);
            $evaluation = logisticEvaluate($binary->weights, $vectors, $data->test->targets);
            $losses += $evaluation->loss;
            $numerators += auc($evaluation->probabilities, $data->test->targets)[0];
            $classRows = softmaxEvaluate($multiclass->weights, $vectors, $data->test->labels)->rows;
            foreach ($classRows as $index => $row) {
                $correct += (int) ($row->predicted === $data->test->labels[$index]);
            }
        }
        $results[] = (object) ['name' => $name, 'increase' => $losses / $repetitions - $binary->test->loss,
            'auc' => [$numerators, $repetitions * $binary->auc[1]], 'correct' => $correct, 'total' => $repetitions * $data->test->count];
    }
    return $results;
}

function predictPoint(object $data, object $binary, object $multiclass, array $base): object
{
    $vector = standardizeOne(expand($base, $data->features), $data->statistics);
    $result = softmaxRow($multiclass->weights, $vector);
    $result->probability = sigmoid(score($binary->weights, $vector));
    return $result;
}

function profiles(object $data, object $binary, object $multiclass): array
{
    $results = [];
    foreach ($data->names as $feature => $name) {
        $bounds = $data->bounds[$feature];
        for ($point = 0; $point <= 4; $point++) {
            $base = $data->baseMean;
            $base[$feature] = $bounds->low + ($bounds->high - $bounds->low) * $point / 4.0;
            $prediction = predictPoint($data, $binary, $multiclass, $base);
            $prediction->name = $name;
            $prediction->value = $base[$feature];
            $results[] = $prediction;
        }
    }
    return $results;
}

function oneVersusRest(object $data, object $multiclass): object
{
    $lambda = $data->settings->softmax[2];
    $classes = [];
    for ($label = 0; $label < $data->classes; $label++) {
        $targets = array_map(fn($value) => (int) ($value === $label), $data->train->labels);
        $testTargets = array_map(fn($value) => (int) ($value === $label), $data->test->labels);
        $fitted = newton($data->train->vectors, $targets, $lambda);
        $evaluation = logisticEvaluate($fitted->weights, $data->test->vectors, $testTargets);
        $classes[] = (object) ['label' => $label, 'objective' => logisticEvaluate($fitted->weights, $data->train->vectors, $targets, $lambda)->objective,
            'probabilities' => $evaluation->probabilities, 'auc' => auc($evaluation->probabilities, $testTargets)];
    }
    $correct = $agreement = 0;
    for ($row = 0; $row < $data->test->count; $row++) {
        $predicted = 0;
        for ($label = 1; $label < $data->classes; $label++) {
            if ($classes[$label]->probabilities[$row] > $classes[$predicted]->probabilities[$row]) {
                $predicted = $label;
            }
        }
        $correct += (int) ($predicted === $data->test->labels[$row]);
        $agreement += (int) ($predicted === $multiclass->rows[$row]->predicted);
    }
    return (object) compact('classes', 'correct', 'agreement');
}

function predictionMaps(object $data, object $binary, object $multiclass): object
{
    [$width, $height] = $data->settings->map;
    $first = $data->bounds[0];
    $second = $data->bounds[1];
    $classes = $probabilities = [];
    $counts = array_fill(0, $data->classes, 0);
    for ($row = 0; $row < $height; $row++) {
        $classLine = $probabilityLine = '';
        for ($column = 0; $column < $width; $column++) {
            $base = $data->baseMean;
            $base[0] = $first->low + ($column + 0.5) * ($first->high - $first->low) / $width;
            $base[1] = $second->high - ($row + 0.5) * ($second->high - $second->low) / $height;
            $prediction = predictPoint($data, $binary, $multiclass, $base);
            $classLine .= $prediction->predicted;
            $probabilityLine .= min(9, (int) floor($prediction->probability * 10));
            $counts[$prediction->predicted]++;
        }
        $classes[] = $classLine;
        $probabilities[] = $probabilityLine;
    }
    return (object) compact('classes', 'probabilities', 'counts');
}

function sections(array $parts): array
{
    $lines = [];
    foreach ($parts as $index => $part) {
        if ($index > 0) {
            $lines[] = '';
        }
        array_push($lines, ...$part);
    }
    return $lines;
}

function termLines(object $data, array $weights): array
{
    $original = originalWeights($weights, $data->statistics);
    $names = array_merge(['intercept'], array_map(fn($feature) => $feature->name, $data->features));
    $lines = [];
    foreach ($names as $component => $name) {
        $lines[] = 'term ' . $name . ' standardized ' . formatReal($weights[$component]) . ' original ' . formatReal($original[$component]);
    }
    return $lines;
}

function weightsReport(object $data, object $state): array
{
    $features = ['features ' . count($data->names) . ' degree ' . $data->settings->degree . ' expanded ' . count($data->features), 'standardization'];
    foreach ($data->features as $index => $feature) {
        $features[] = $feature->name . ' mean ' . formatReal($data->statistics->means[$index], 6) . ' sd ' .
            formatReal($data->statistics->deviations[$index], 6) . ' vif ' . formatReal($state->correlations->vif[$index]);
    }
    $features[] = 'correlation';
    foreach ($state->correlations->matrix as $row) {
        $features[] = implode(' ', array_map(fn($value) => formatReal($value), $row));
    }
    $parts = [$features];
    $binary = $state->models[2];
    foreach ($state->models as $model) {
        $lines = ['model ' . $model->name . ' lambda ' . formatReal($state->lambda)];
        array_push($lines, ...termLines($data, $model->weights));
        $lines[] = 'norm ' . formatReal($model->norm);
        if ($model->name !== 'newton') {
            $difference = [];
            foreach ($model->weights as $index => $weight) {
                $difference[] = $weight - $binary->weights[$index];
            }
            $lines[] = 'distance_to_newton ' . formatReal(vectorLength($difference), 6);
        }
        $parts[] = $lines;
    }
    $coefficients = ['coefficients newton lambda ' . formatReal($state->lambda)];
    $names = array_merge(['intercept'], array_map(fn($feature) => $feature->name, $data->features));
    foreach ($binary->weights as $component => $weight) {
        $se = sqrt($state->influence->matrix[$component][$component] / $data->train->count);
        $coefficients[] = $names[$component] . ' weight ' . formatReal($weight) . ' se ' . formatReal($se) . ' z ' . formatReal($weight / $se) .
            ' lower ' . formatReal($weight - 1.96 * $se) . ' upper ' . formatReal($weight + 1.96 * $se) . ' odds_ratio ' . formatReal(exp($weight));
    }
    $parts[] = $coefficients;
    $multiclass = ['model softmax lambda ' . formatReal($data->settings->softmax[2])];
    foreach ($state->softmax->weights as $label => $weights) {
        $multiclass[] = 'class ' . $label;
        array_push($multiclass, ...termLines($data, $weights));
    }
    $parts[] = $multiclass;
    return sections($parts);
}

function lossTrace(object $data, object $state): array
{
    $lines = ['optimizer,iteration,loss,gradient_norm,test_loss'];
    foreach ($state->models as $model) {
        foreach ($model->checkpoints as $checkpoint) {
            $training = logisticEvaluate($checkpoint->weights, $data->train->vectors, $data->train->targets, $state->lambda);
            $direction = logisticGradient($checkpoint->weights, $data->train->vectors, $data->train->targets, $state->lambda);
            $testing = logisticEvaluate($checkpoint->weights, $data->test->vectors, $data->test->targets);
            $lines[] = implode(',', [$model->name, $checkpoint->iteration, formatReal($training->objective, 6), formatReal(vectorLength($direction), 6), formatReal($testing->loss, 6)]);
        }
    }
    foreach ($state->softmax->checkpoints as $checkpoint) {
        $training = softmaxEvaluate($checkpoint->weights, $data->train->vectors, $data->train->labels, $data->settings->softmax[2]);
        $direction = softmaxGradient($checkpoint->weights, $data->train->vectors, $data->train->labels, $data->settings->softmax[2]);
        $testing = softmaxEvaluate($checkpoint->weights, $data->test->vectors, $data->test->labels);
        $flat = [];
        foreach ($direction as $row) {
            array_push($flat, ...$row);
        }
        $lines[] = implode(',', ['softmax', $checkpoint->iteration, formatReal($training->objective, 6), formatReal(vectorLength($flat), 6), formatReal($testing->loss, 6)]);
    }
    return $lines;
}

function predictionsReport(object $data, object $state): array
{
    $lines = ['id,model,probability,predicted,actual'];
    foreach ($state->models as $model) {
        foreach ($data->test->ids as $index => $id) {
            $lines[] = implode(',', [$id, $model->name, formatReal($model->test->probabilities[$index], 6),
                $model->confusion->predictions[$index], $data->test->targets[$index]]);
        }
    }
    foreach ($state->softmax->rows as $index => $row) {
        $lines[] = implode(',', [$data->test->ids[$index], 'softmax', formatReal($row->probabilities[$row->predicted], 6), $row->predicted, $data->test->labels[$index]]);
    }
    return $lines;
}

function rocReport(object $data, array $models): array
{
    $lines = ['model,threshold,tpr,fpr,precision'];
    foreach ($models as $model) {
        $lines[] = $model->name . ',inf,0.0000,0.0000,-';
        foreach ($model->points as $point) {
            $lines[] = implode(',', [$model->name, formatReal($point->threshold, 6), ratio($point->tp, $data->test->positive),
                ratio($point->fp, $data->test->count - $data->test->positive), ratio($point->tp, $point->tp + $point->fp)]);
        }
    }
    return $lines;
}

function dataLines(object $data): array
{
    return ['data train ' . $data->train->count . ' test ' . $data->test->count . ' base_features ' . count($data->names) .
            ' degree ' . $data->settings->degree . ' features ' . count($data->features),
        'binary positive_class ' . $data->settings->positive . ' train ' . $data->train->positive . '/' . $data->train->count .
            ' test ' . $data->test->positive . '/' . $data->test->count,
        'classes ' . $data->classes . ' train ' . implode(' ', $data->train->classCounts) . ' test ' . implode(' ', $data->test->classCounts)];
}

function crossValidationLines(object $data, object $validation): array
{
    $lines = ['cross_validation folds 5 newton_iterations 10'];
    foreach ($validation->candidates as $candidate) {
        $folds = implode(' ', array_map(fn($value) => formatReal($value, 6), $candidate->foldLosses));
        $lines[] = 'lambda ' . formatReal($candidate->lambda) . ' fold_loss ' . $folds . ' cv_loss ' . formatReal($candidate->loss, 6) .
            ' errors ' . $candidate->errors . '/' . $data->train->count;
    }
    $lines[] = 'selected lambda ' . formatReal($validation->selected->lambda) . ' cv_loss ' . formatReal($validation->selected->loss, 6) .
        ' se ' . formatReal($validation->se, 6) . ' lambda_1se ' . formatReal($validation->oneSE);
    $table = $validation->confusion;
    $lines[] = 'out_of_fold tp ' . $table->tp . ' fp ' . $table->fp . ' tn ' . $table->tn . ' fn ' . $table->fn .
        ' accuracy ' . ratio($table->tp + $table->tn, $data->train->count) . ' auc ' . fraction($validation->auc);
    return $lines;
}

function pathLines(object $data, array $path): array
{
    $lines = ['lambda_path'];
    foreach ($path as $model) {
        $lines[] = 'lambda ' . formatReal($model->lambda) . ' objective ' . formatReal($model->train->objective, 6) .
            ' train_loss ' . formatReal($model->train->loss, 6) . ' test_loss ' . formatReal($model->test->loss, 6) .
            ' train_accuracy ' . ratio($model->trainCorrect, $data->train->count) . ' test_accuracy ' . ratio($model->testCorrect, $data->test->count) .
            ' norm ' . formatReal($model->norm);
    }
    return $lines;
}

function degreeLines(object $data, object $state): array
{
    $lines = ['degrees lambda ' . formatReal($state->lambda)];
    foreach ($state->degrees as $degree) {
        $lines[] = 'degree ' . $degree->degree . ' features ' . $degree->width . ' cv_loss ' . formatReal($degree->cv, 6) .
            ' train_loss ' . formatReal($degree->train->loss, 6) . ' test_loss ' . formatReal($degree->test->loss, 6) .
            ' test_accuracy ' . ratio($degree->testCorrect, $data->test->count) . ' auc ' . fraction($degree->auc) .
            ' edf ' . formatReal($degree->influence->edf) . ' aic ' . formatReal($degree->influence->aic) . ' bic ' . formatReal($degree->influence->bic);
    }
    return $lines;
}

function learningLines(object $data, object $state): array
{
    $lines = ['learning_curve lambda ' . formatReal($state->lambda)];
    foreach ($state->learning as $model) {
        $lines[] = 'size ' . $model->size . ' train_loss ' . formatReal($model->train->loss, 6) . ' test_loss ' . formatReal($model->test->loss, 6) .
            ' test_accuracy ' . ratio($model->testCorrect, $data->test->count) . ' auc ' . fraction($model->auc);
    }
    return $lines;
}

function binRange(int $index): string
{
    return '0.' . $index . '-' . ($index === 9 ? '1.0' : '0.' . ($index + 1));
}

function binaryLines(object $data, object $model, float $lambda): array
{
    $table = $model->confusion;
    $positive = $data->test->positive;
    $negative = $data->test->count - $positive;
    $youden = $model->youden;
    $best = $model->bestF1;
    $cost = $model->minCost;
    $lines = [
        'model ' . $model->name . ' lambda ' . formatReal($lambda),
        'train correct ' . $model->trainCorrect . '/' . $data->train->count . ' accuracy ' . ratio($model->trainCorrect, $data->train->count),
        'test tp ' . $table->tp . ' fp ' . $table->fp . ' tn ' . $table->tn . ' fn ' . $table->fn,
        'test accuracy ' . ratio($table->tp + $table->tn, $data->test->count) . ' precision ' . ratio($table->tp, $table->tp + $table->fp) .
            ' recall ' . ratio($table->tp, $table->tp + $table->fn) . ' specificity ' . ratio($table->tn, $table->tn + $table->fp) .
            ' f1 ' . ratio(2 * $table->tp, 2 * $table->tp + $table->fp + $table->fn),
        'log_loss ' . formatReal($model->test->loss, 6) . ' brier ' . formatReal($model->brier, 6),
        'auc ' . fraction($model->auc) . ' average_precision ' . formatReal($model->averagePrecision),
        'youden threshold ' . formatReal($youden->threshold, 6) . ' tpr ' . ratio($youden->tp, $positive) . ' fpr ' . ratio($youden->fp, $negative) .
            ' j ' . ratio($youden->tp * $negative - $youden->fp * $positive, $positive * $negative),
        'best_f1 threshold ' . formatReal($best->threshold, 6) . ' precision ' . ratio($best->tp, $best->tp + $best->fp) .
            ' recall ' . ratio($best->tp, $positive) . ' f1 ' . ratio(2 * $best->tp, $positive + $best->tp + $best->fp),
        'min_cost threshold ' . formatReal($cost->threshold, 6) . ' cost ' . $cost->cost . ' fp ' . $cost->fp . ' fn ' . ($positive - $cost->tp),
        'calibration'
    ];
    foreach ($model->calibration->bins as $index => $bin) {
        $mean = $bin->count === 0 ? null : $bin->total / $bin->count;
        $lines[] = 'bin ' . binRange($index) . ' count ' . $bin->count . ' mean_probability ' . formatReal($mean) .
            ' positive_rate ' . ratio($bin->positives, $bin->count);
    }
    $calibration = $model->calibration;
    $lines[] = 'ece ' . formatReal($calibration->ece) . ' mce ' . formatReal($calibration->mce) .
        ' hosmer_lemeshow ' . formatReal($calibration->hl) . ' groups ' . $calibration->groups;
    $lines[] = 'gains';
    foreach ($model->gains as $gain) {
        $lines[] = 'decile ' . $gain->decile . ' rows ' . $gain->size . ' positives ' . $gain->hits .
            ' gain ' . ratio($gain->hits, $positive) . ' lift ' . ratio($gain->hits * $data->test->count, $gain->size * $positive);
    }
    return $lines;
}

function agreementLines(object $data, array $models): array
{
    $lines = [];
    foreach ([[0, 1], [0, 2], [1, 2]] as [$first, $second]) {
        $a = $models[$first];
        $b = $models[$second];
        $same = $onlyFirst = $onlySecond = 0;
        for ($row = 0; $row < $data->test->count; $row++) {
            $predictionA = $a->confusion->predictions[$row];
            $predictionB = $b->confusion->predictions[$row];
            if ($predictionA === $predictionB) {
                $same++;
            } elseif ($predictionA === $data->test->targets[$row]) {
                $onlyFirst++;
            } else {
                $onlySecond++;
            }
        }
        $corrected = abs($onlyFirst - $onlySecond) - 1;
        $lines[] = 'agreement ' . $a->name . ' ' . $b->name . ' same ' . $same . '/' . $data->test->count .
            ' only_first ' . $onlyFirst . ' only_second ' . $onlySecond . ' mcnemar ' . ratio($corrected * $corrected, $onlyFirst + $onlySecond);
    }
    return $lines;
}

function diagnosticLines(object $data, object $state): array
{
    $diagnostic = $state->diagnostics;
    $measures = $state->influence;
    $model = $state->models[2];
    $lines = [
        'diagnostics newton lambda ' . formatReal($state->lambda),
        'fit null_loss ' . formatReal($diagnostic->nullLoss, 6) . ' train_loss ' . formatReal($measures->loss, 6) .
            ' mcfadden_r2 ' . formatReal($diagnostic->mcfadden) . ' deviance ' . formatReal($measures->deviance) . ' edf ' . formatReal($measures->edf) .
            ' aic ' . formatReal($measures->aic) . ' bic ' . formatReal($measures->bic),
        'hosmer_lemeshow_train groups 10 statistic ' . formatReal($diagnostic->hl)
    ];
    foreach ($diagnostic->groups as $group) {
        $lines[] = 'group ' . $group->group . ' rows ' . $group->size . ' observed ' . $group->observed . ' expected ' . formatReal($group->expected);
    }
    $lines[] = 'newton_iterations';
    foreach ($diagnostic->iterations as $iteration) {
        $lines[] = 'iteration ' . $iteration->iteration . ' objective ' . formatReal($iteration->objective, 6) .
            ' gradient_norm ' . formatReal($iteration->gradient, 6) . ' step_norm ' . formatReal($iteration->step, 6) .
            ' predicted_decrease ' . formatReal($iteration->decrease, 6);
    }
    foreach ($diagnostic->marginals as $marginal) {
        $lines[] = 'marginal ' . $marginal->name . ' average ' . formatReal($marginal->average) . ' at_mean ' . formatReal($marginal->atMean);
    }
    foreach ($diagnostic->thresholds as $cut) {
        $lines[] = 'cut 0.' . $cut->digit . ' positive ' . ($cut->tp + $cut->fp) . ' tp ' . $cut->tp . ' fp ' . $cut->fp .
            ' precision ' . ratio($cut->tp, $cut->tp + $cut->fp) . ' recall ' . ratio($cut->tp, $cut->tp + $cut->fn) .
            ' accuracy ' . ratio($cut->tp + $cut->tn, $data->test->count);
    }
    foreach ($diagnostic->errors as $row) {
        $lines[] = 'error ' . $data->test->ids[$row] . ' actual ' . $data->test->targets[$row] . ' probability ' . formatReal($model->test->probabilities[$row], 6);
    }
    $resampling = $diagnostic->bootstrap;
    $lines[] = 'bootstrap resamples ' . $data->settings->bootstrap[0] . ' seed ' . $data->settings->bootstrap[1] .
        ' auc_mean ' . formatReal($resampling->mean) . ' auc_sd ' . formatReal($resampling->sd) .
        ' lower ' . fraction($resampling->lower) . ' upper ' . fraction($resampling->upper);
    $lines[] = 'influence effective_parameters ' . formatReal($measures->edf) . ' large_residuals ' . $diagnostic->largeResiduals;
    foreach ($diagnostic->cooks as $row) {
        $lines[] = 'cook ' . $data->train->ids[$row->index] . ' actual ' . $data->train->targets[$row->index] .
            ' probability ' . formatReal($row->probability) . ' leverage ' . formatReal($row->leverage) . ' residual ' . formatReal($row->residual) . ' distance ' . formatReal($row->cook);
    }
    return $lines;
}

function importanceLines(object $data, object $state): array
{
    $binary = $state->models[2];
    $lines = ['importance repeats ' . $data->settings->permutation[0] . ' seed ' . $data->settings->permutation[1],
        'baseline log_loss ' . formatReal($binary->test->loss, 6) . ' auc ' . fraction($binary->auc) .
            ' softmax_accuracy ' . ratio($state->softmax->correct, $data->test->count)];
    foreach ($state->importance as $feature) {
        $lines[] = 'feature ' . $feature->name . ' log_loss_increase ' . formatReal($feature->increase, 6) .
            ' auc ' . fraction($feature->auc) . ' softmax_accuracy ' . ratio($feature->correct, $feature->total);
    }
    return $lines;
}

function profileLines(array $profiles): array
{
    $lines = ['profiles'];
    foreach ($profiles as $point) {
        $values = implode(' ', array_map(fn($value) => formatReal($value), $point->probabilities));
        $lines[] = 'profile ' . $point->name . ' value ' . formatReal($point->value) . ' newton ' . formatReal($point->probability) . ' softmax ' . $values;
    }
    return $lines;
}

function softmaxLines(object $data, object $model): array
{
    $lines = ['softmax classes ' . $data->classes . ' lambda ' . formatReal($data->settings->softmax[2]) .
        ' iterations ' . $data->settings->softmax[1], 'confusion'];
    foreach ($model->table as $row) {
        $lines[] = implode(' ', $row);
    }
    for ($label = 0; $label < $data->classes; $label++) {
        $diagonal = $model->table[$label][$label];
        $lines[] = 'class ' . $label . ' precision ' . ratio($diagonal, $model->columnTotals[$label]) .
            ' recall ' . ratio($diagonal, $model->rowTotals[$label]) .
            ' f1 ' . ratio(2 * $diagonal, $model->columnTotals[$label] + $model->rowTotals[$label]) . ' auc ' . fraction($model->classAUC[$label]);
    }
    $lines[] = 'accuracy ' . ratio($model->correct, $data->test->count) . ' kappa ' . ratio($model->kappa[0], $model->kappa[1]);
    $lines[] = 'log_loss ' . formatReal($model->loss, 6) . ' brier ' . formatReal($model->brier, 6);
    $lines[] = 'binary_view positive_class ' . $data->settings->positive . ' auc ' . fraction($model->binaryAUC) .
        ' log_loss ' . formatReal($model->binaryLoss, 6) . ' accuracy ' . ratio($model->binaryConfusion->correct, $data->test->count) .
        ' agreement_with_newton ' . $model->agreement . '/' . $data->test->count;
    $lines[] = 'confidence';
    foreach ($model->bins as $index => $bin) {
        $mean = $bin->count === 0 ? null : $bin->total / $bin->count;
        $lines[] = 'bin ' . binRange($index) . ' count ' . $bin->count . ' mean_confidence ' . formatReal($mean) . ' accuracy ' . ratio($bin->hits, $bin->count);
    }
    $lines[] = 'ece ' . formatReal($model->ece);
    return $lines;
}

function oneVersusRestLines(object $data, object $result): array
{
    $lines = ['one_vs_rest lambda ' . formatReal($data->settings->softmax[2]) . ' newton_iterations 10'];
    foreach ($result->classes as $model) {
        $lines[] = 'class ' . $model->label . ' objective ' . formatReal($model->objective, 6) . ' auc ' . fraction($model->auc);
    }
    $lines[] = 'accuracy ' . ratio($result->correct, $data->test->count) . ' agreement_with_softmax ' . $result->agreement . '/' . $data->test->count;
    return $lines;
}

function mapLines(object $data, object $maps): array
{
    $lines = ['map ' . $data->names[0] . ' ' . $data->names[1] . ' width ' . $data->settings->map[0] . ' height ' . $data->settings->map[1],
        'softmax_classes'];
    array_push($lines, ...$maps->classes);
    $lines[] = 'cells ' . implode(' ', $maps->counts);
    $lines[] = 'newton_probability';
    array_push($lines, ...$maps->probabilities);
    return $lines;
}

function evaluationReport(object $data, object $state): array
{
    $parts = [dataLines($data), crossValidationLines($data, $state->validation), pathLines($data, $state->path),
        degreeLines($data, $state), learningLines($data, $state)];
    foreach ($state->models as $model) {
        $parts[] = binaryLines($data, $model, $state->lambda);
    }
    array_push($parts, agreementLines($data, $state->models), diagnosticLines($data, $state), importanceLines($data, $state),
        profileLines($state->profiles), softmaxLines($data, $state->softmax), oneVersusRestLines($data, $state->oneVersusRest), mapLines($data, $state->maps));
    return sections($parts);
}

$data = prepareData();
$validation = selectLambda($data);
$lambda = $validation->selected->lambda;
$models = array_map(fn($fitted) => binaryAnalysis($data, $fitted, $lambda), trainModels($data, $lambda));
[$rate, $iterations, $softmaxLambda] = $data->settings->softmax;
$softmax = trainSoftmax($data->train->vectors, $data->train->labels, $data->classes, $softmaxLambda, $rate, $iterations);
$multiclass = multiclassAnalysis($data, $softmax, $models[2]);
$measures = influence($models[2]->weights, $data->train->vectors, $data->train->targets, $lambda);
$state = (object) ['validation' => $validation, 'lambda' => $lambda, 'models' => $models, 'softmax' => $multiclass,
    'influence' => $measures, 'correlations' => featureCorrelations($data), 'path' => lambdaPath($data),
    'degrees' => degreeComparison($data, $lambda), 'learning' => learningCurve($data, $lambda),
    'diagnostics' => newtonDiagnostics($data, $models[2], $lambda, $measures),
    'importance' => permutationImportance($data, $models[2], $multiclass), 'profiles' => profiles($data, $models[2], $multiclass),
    'oneVersusRest' => oneVersusRest($data, $multiclass), 'maps' => predictionMaps($data, $models[2], $multiclass)];
$reports = ['weights.txt' => weightsReport($data, $state), 'loss_trace.csv' => lossTrace($data, $state),
    'predictions.csv' => predictionsReport($data, $state), 'evaluation.txt' => evaluationReport($data, $state), 'roc.csv' => rocReport($data, $models)];
if (!is_dir('output')) {
    mkdir('output', 0777, true);
}
foreach ($reports as $name => $lines) {
    file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}
