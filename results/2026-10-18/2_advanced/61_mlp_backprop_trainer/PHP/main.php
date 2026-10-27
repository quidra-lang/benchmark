<?php

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/layers.php';
require_once __DIR__ . '/network.php';
require_once __DIR__ . '/optimizers.php';
require_once __DIR__ . '/evaluation.php';

function evaluate(Network $network, array $theta, array $images): object
{
    $results = [];
    $totalLoss = 0.0;
    $correct = 0;
    foreach ($images as $image) {
        $result = $network->forward($theta, $image);
        $result->predicted = prediction($result->scores);
        $result->correct = $result->predicted === $image->label;
        $result->confidence = $result->scores[$result->predicted];
        $totalLoss += $result->loss;
        if ($result->correct) {
            $correct++;
        }
        $results[] = $result;
    }
    return (object) ['results' => $results, 'correct' => $correct, 'loss' => $totalLoss / count($images)];
}

function meanGradient(Network $network, array $theta, array $images): array
{
    $mean = array_fill(0, $network->parameterCount, 0.0);
    foreach ($images as $image) {
        $result = $network->forward($theta, $image);
        $gradient = $network->backward($theta, $result)->gradient;
        foreach ($gradient as $p => $value) {
            $mean[$p] += $value;
        }
    }
    foreach ($mean as &$value) {
        $value /= count($images);
    }
    unset($value);
    return $mean;
}

function checkNetwork(Network $network, object $data, object $settings): array
{
    $generator = new Minstd($settings->seed);
    $order = range(0, count($data->train) - 1);
    $generator->shuffle($order);
    $batch = [];
    foreach (array_slice($order, 0, min($settings->batchSize, count($order))) as $index) {
        $batch[] = $data->train[$index];
    }
    $theta = $network->initial;
    $analytic = meanGradient($network, $theta, $batch);
    $counts = array_fill(0, count($network->layers), ['weights' => 0, 'biases' => 0]);
    $checked = 0;
    $passed = true;
    $h = 0.00001;
    for ($p = 0; $p < $network->parameterCount; $p += $settings->stride) {
        $original = $theta[$p];
        $theta[$p] = $original + $h;
        $plus = evaluate($network, $theta, $batch)->loss;
        $theta[$p] = $original - $h;
        $minus = evaluate($network, $theta, $batch)->loss;
        $theta[$p] = $original;
        $numerical = ($plus - $minus) / (2 * $h);
        $error = abs($analytic[$p] - $numerical) / max(1, abs($analytic[$p]) + abs($numerical));
        if (!($error < 0.000001)) {
            $passed = false;
        }
        foreach ($network->layers as $l => $layer) {
            if ($p < $layer->end) {
                $counts[$l][$p < $layer->biasOffset ? 'weights' : 'biases']++;
                break;
            }
        }
        $checked++;
    }
    $ids = array_map(fn($image) => $image->id, $batch);
    $lines = ['network ' . $network->name, 'parameters ' . $network->parameterCount, 'batch ' . implode(' ', $ids)];
    foreach ($counts as $l => $count) {
        $lines[] = 'layer ' . ($l + 1) . ' weights ' . $count['weights'] . ' biases ' . $count['biases'];
    }
    $lines[] = 'checked ' . $checked;
    $lines[] = 'result ' . ($passed ? 'PASS' : 'FAIL');
    return $lines;
}

function trainRun(object $run, Network $network, object $data, object $settings): object
{
    $theta = $network->initial;
    $generator = new Minstd($settings->seed);
    $optimizer = new Optimizer($run, $network->parameterCount);
    $order = range(0, count($data->train) - 1);
    $history = [];
    $best = null;
    $wait = 0;
    $updates = 0;
    $stop = 'max_epochs';
    for ($epoch = 1; $epoch <= $settings->maxEpochs; $epoch++) {
        $rate = learningRate($run, $settings, $epoch);
        $generator->shuffle($order);
        $magnitude = 0.0;
        $batches = 0;
        for ($start = 0; $start < count($order); $start += $settings->batchSize) {
            $batch = [];
            foreach (array_slice($order, $start, $settings->batchSize) as $index) {
                $batch[] = $data->train[$index];
            }
            $gradient = meanGradient($network, $theta, $batch);
            foreach ($network->weightIndices as $p) {
                $gradient[$p] += $run->decay * $theta[$p];
            }
            $squared = 0.0;
            foreach ($gradient as $component) {
                $squared += $component * $component;
            }
            $magnitude += sqrt($squared);
            $optimizer->update($theta, $gradient, $rate);
            $batches++;
            $updates++;
        }
        $training = evaluate($network, $theta, $data->train);
        $validation = evaluate($network, $theta, $data->validation);
        $improved = $best === null || $validation->loss < $best->loss;
        if ($improved) {
            $best = (object) ['theta' => $theta, 'epoch' => $epoch, 'loss' => $validation->loss, 'correct' => $validation->correct];
            $wait = 0;
        } else {
            $wait++;
        }
        $history[] = (object) ['epoch' => $epoch, 'rate' => $rate, 'magnitude' => $magnitude / $batches,
            'trainLoss' => $training->loss, 'trainCorrect' => $training->correct,
            'validationLoss' => $validation->loss, 'validationCorrect' => $validation->correct,
            'correct' => array_map(fn($result) => $result->correct, $training->results), 'improved' => $improved];
        if ($wait >= $settings->patience) {
            $stop = 'early';
            break;
        }
    }
    return (object) ['run' => $run, 'network' => $network, 'theta' => $best->theta, 'best' => $best,
        'history' => $history, 'epochs' => count($history), 'updates' => $updates, 'stop' => $stop];
}

function forgetting(array $history, int $count): object
{
    $events = 0;
    $rows = 0;
    $neverLearned = 0;
    for ($i = 0; $i < $count; $i++) {
        $forgotten = 0;
        $learned = false;
        foreach ($history as $e => $epoch) {
            if ($epoch->correct[$i]) {
                $learned = true;
            }
            if ($e > 0 && $history[$e - 1]->correct[$i] && !$epoch->correct[$i]) {
                $forgotten++;
            }
        }
        $events += $forgotten;
        if ($forgotten > 0) {
            $rows++;
        }
        if (!$learned) {
            $neverLearned++;
        }
    }
    return (object) ['events' => $events, 'rows' => $rows, 'neverLearned' => $neverLearned];
}

function weightStatistics(Network $network, array $theta): object
{
    $norms = [];
    $changes = [];
    foreach ($network->layers as $layer) {
        $squared = 0.0;
        $changed = 0.0;
        for ($p = $layer->offset; $p < $layer->biasOffset; $p++) {
            $squared += $theta[$p] * $theta[$p];
            $difference = $theta[$p] - $network->initial[$p];
            $changed += $difference * $difference;
        }
        $norms[] = sqrt($squared);
        $changes[] = sqrt($changed);
    }
    return (object) ['norms' => $norms, 'changes' => $changes];
}

function noisyData(array $images, int $rate, int $seed): object
{
    $generator = new Minstd($seed);
    $changed = [];
    $flipped = 0;
    foreach ($images as $image) {
        $vector = [];
        foreach ($image->vector as $pixel) {
            $flip = $generator->next() % 100 < $rate;
            $vector[] = $flip ? 1.0 - $pixel : $pixel;
            if ($flip) {
                $flipped++;
            }
        }
        $copy = clone $image;
        $copy->vector = $vector;
        $copy->pixels = implode('', $vector);
        $changed[] = $copy;
    }
    return (object) ['rate' => $rate, 'images' => $changed, 'flipped' => $flipped];
}

function calibration(array $results, int $size): object
{
    $bins = [];
    for ($i = 0; $i < $size; $i++) {
        $bins[] = (object) ['count' => 0, 'correct' => 0, 'totalConfidence' => 0.0];
    }
    foreach ($results as $result) {
        $index = min($size - 1, (int) floor($result->confidence * $size));
        $bin = $bins[$index];
        $bin->count++;
        if ($result->correct) {
            $bin->correct++;
        }
        $bin->totalConfidence += $result->confidence;
    }
    $ece = 0.0;
    foreach ($bins as $bin) {
        $bin->mean = $bin->count === 0 ? null : $bin->totalConfidence / $bin->count;
        if ($bin->count > 0) {
            $ece += ($bin->count / count($results)) * abs($bin->correct / $bin->count - $bin->mean);
        }
    }
    return (object) ['bins' => $bins, 'ece' => $ece];
}

function hiddenStatistics(Network $network, array $images, array $results): array
{
    $statistics = [];
    for ($l = 0; $l < count($network->layers) - 1; $l++) {
        $layer = $network->layers[$l];
        $sums = array_fill(0, $network->classes, array_fill(0, $layer->units, 0.0));
        $counts = array_fill(0, $network->classes, 0);
        $zeroCounts = array_fill(0, $layer->units, 0);
        foreach ($images as $i => $image) {
            $label = $image->label;
            $counts[$label]++;
            for ($j = 0; $j < $layer->units; $j++) {
                $value = $results[$i]->activations[$l + 1][$j];
                $sums[$label][$j] += $value;
                if ($value == 0.0) {
                    $zeroCounts[$j]++;
                }
            }
        }
        $means = [];
        for ($k = 0; $k < $network->classes; $k++) {
            if ($counts[$k] === 0) {
                $means[] = null;
            } else {
                $means[] = array_map(fn($value) => $value / $counts[$k], $sums[$k]);
            }
        }
        $preferred = [];
        for ($j = 0; $j < $layer->units; $j++) {
            $best = null;
            for ($k = 0; $k < $network->classes; $k++) {
                if ($means[$k] !== null && ($best === null || $means[$k][$j] > $means[$best][$j])) {
                    $best = $k;
                }
            }
            $preferred[] = $best;
        }
        $statistics[] = (object) ['layer' => $layer, 'means' => $means, 'preferred' => $preferred, 'zeroCounts' => $zeroCounts];
    }
    return $statistics;
}

function evaluateRun(object $trained, object $data, object $settings, array $noisy): object
{
    $network = $trained->network;
    $theta = $trained->theta;
    $test = evaluate($network, $theta, $data->test);
    $matrix = confusion($data->test, $test->results, $network->classes);
    $confidenceSums = [0.0, 0.0];
    $topTwo = 0;
    $misclassified = [];
    foreach ($test->results as $i => $result) {
        if ($result->correct || secondClass($result->scores, $result->predicted) === $data->test[$i]->label) {
            $topTwo++;
        }
        $confidenceSums[$result->correct ? 0 : 1] += $result->confidence;
        if (!$result->correct) {
            $misclassified[] = $i;
        }
    }
    $sortedWeights = $network->weightIndices;
    usort($sortedWeights, fn($a, $b) => (abs($theta[$a]) <=> abs($theta[$b])) ?: ($a <=> $b));
    $pruning = [];
    foreach ($settings->prune as $percent) {
        $removed = intdiv($percent * count($sortedWeights), 100);
        $pruned = $theta;
        for ($i = 0; $i < $removed; $i++) {
            $pruned[$sortedWeights[$i]] = 0.0;
        }
        $result = evaluate($network, $pruned, $data->test);
        $pruning[] = (object) ['percent' => $percent, 'removed' => $removed, 'correct' => $result->correct, 'loss' => $result->loss];
    }
    $noise = [];
    foreach ($noisy as $group) {
        $noise[] = (object) ['rate' => $group->rate, 'correct' => evaluate($network, $theta, $group->images)->correct];
    }
    $trained->test = $test;
    $trained->matrix = $matrix;
    $trained->topTwo = $topTwo;
    $trained->misclassified = $misclassified;
    $trained->pruning = $pruning;
    $trained->noise = $noise;
    $trained->confidenceCorrect = $test->correct === 0 ? null : $confidenceSums[0] / $test->correct;
    $trained->confidenceWrong = !$misclassified ? null : $confidenceSums[1] / count($misclassified);
    $trained->forgetting = forgetting($trained->history, count($data->train));
    $trained->weights = weightStatistics($network, $theta);
    $trained->calibration = calibration($test->results, $settings->bins);
    $trained->hidden = hiddenStatistics($network, $data->test, $test->results);
    return $trained;
}

function classCounts(array $images, int $size): array
{
    $counts = array_fill(0, $size, 0);
    foreach ($images as $image) {
        $counts[$image->label]++;
    }
    return $counts;
}

function dataReport(object $data): array
{
    $training = classCounts($data->train, $data->classes);
    $validation = classCounts($data->validation, $data->classes);
    $test = classCounts($data->test, $data->classes);
    $pixels = array_fill(0, $data->classes, array_fill(0, $data->pixels, 0));
    $ink = array_fill(0, $data->classes, 0);
    foreach ($data->train as $image) {
        for ($i = 0; $i < $data->pixels; $i++) {
            $value = $image->pixels[$i] === '1' ? 1 : 0;
            $pixels[$image->label][$i] += $value;
            $ink[$image->label] += $value;
        }
    }
    $lines = ['data', 'train ' . count($data->train) . ' validation ' . count($data->validation)
        . ' test ' . count($data->test) . ' pixels ' . $data->pixels];
    $maps = [];
    for ($k = 0; $k < $data->classes; $k++) {
        $lines[] = 'class ' . $k . ' train ' . $training[$k] . ' validation ' . $validation[$k] . ' test ' . $test[$k]
            . ' ink ' . ratio($ink[$k], $training[$k]);
        $map = [];
        foreach ($pixels[$k] as $value) {
            $map[] = $training[$k] === 0 ? 0 : min(9, intdiv(10 * $value, $training[$k]));
        }
        $maps[] = $map;
    }
    $lines[] = 'mean_images ' . implode(' ', range(0, $data->classes - 1));
    return array_merge($lines, levelMaps($maps, $data->width, $data->height));
}

function learningCurve(object $result): array
{
    $maximum = 0.0;
    foreach ($result->history as $epoch) {
        $maximum = max($maximum, $epoch->trainLoss, $epoch->validationLoss);
    }
    $lines = [];
    foreach ($result->history as $epoch) {
        $row = str_repeat(' ', 40);
        $training = (int) floor(39 * $epoch->trainLoss / $maximum + 0.5);
        $validation = (int) floor(39 * $epoch->validationLoss / $maximum + 0.5);
        $row[$training] = 't';
        $row[$validation] = $training === $validation ? '*' : 'v';
        $lines[] = str_pad((string) $epoch->epoch, 2, ' ', STR_PAD_LEFT) . ' |' . $row . '|'
            . ($epoch->epoch === $result->best->epoch ? ' best' : '');
    }
    return $lines;
}

function runReport(object $result, object $data): array
{
    $run = $result->run;
    $network = $result->network;
    $best = $result->best;
    $test = $result->test;
    $total = count($data->test);
    $lines = ['run ' . $run->name . ' network ' . $network->name . ' optimizer ' . $run->optimizer,
        'epochs ' . $result->epochs . ' best_epoch ' . $best->epoch . ' stop ' . $result->stop . ' updates ' . $result->updates,
        'best_val_loss ' . real($best->loss, 6) . ' best_val_acc ' . ratio($best->correct, count($data->validation))
            . ' correct ' . $best->correct . '/' . count($data->validation),
        'test_loss ' . real($test->loss, 6) . ' test_acc ' . ratio($test->correct, $total) . ' correct ' . $test->correct . '/' . $total,
        'top2_acc ' . ratio($result->topTwo, $total) . ' correct ' . $result->topTwo . '/' . $total,
        'confidence correct ' . real($result->confidenceCorrect) . ' wrong ' . real($result->confidenceWrong),
        'forgetting events ' . $result->forgetting->events . ' rows ' . $result->forgetting->rows . ' never_learned ' . $result->forgetting->neverLearned,
        'weight_norms ' . implode(' ', array_map(fn($value) => real($value), $result->weights->norms)),
        'weight_changes ' . implode(' ', array_map(fn($value) => real($value), $result->weights->changes)), 'curve'];
    array_push($lines, ...learningCurve($result));
    $lines[] = 'confusion';
    foreach ($result->matrix as $k => $row) {
        $lines[] = $k . ': ' . implode(' ', $row);
    }
    foreach (perClass($result->matrix) as $k => $value) {
        $lines[] = 'class ' . $k . ' support ' . $value->support . ' predicted ' . $value->predicted
            . ' precision ' . $value->precision . ' recall ' . $value->recall . ' f1 ' . $value->f1;
    }
    $lines[] = 'calibration';
    $binCount = count($result->calibration->bins);
    foreach ($result->calibration->bins as $i => $bin) {
        $lines[] = 'bin ' . ($i + 1) . ' ' . real($i / $binCount, 2) . ' ' . real(($i + 1) / $binCount, 2)
            . ' count ' . $bin->count . ' accuracy ' . ratio($bin->correct, $bin->count) . ' confidence ' . real($bin->mean);
    }
    $lines[] = 'ece ' . real($result->calibration->ece);
    foreach ($result->hidden as $l => $hidden) {
        $lines[] = 'hidden ' . ($l + 1) . ' ' . $hidden->layer->activation . ' units ' . $hidden->layer->units;
        foreach ($hidden->means as $k => $mean) {
            $values = $mean === null ? '-' : implode(' ', array_map(fn($value) => real($value), $mean));
            $lines[] = 'class ' . $k . ' mean ' . $values;
        }
        $lines[] = 'preferred ' . implode(' ', $hidden->preferred);
        if ($hidden->layer->activation === 'RELU') {
            $lines[] = 'zero_counts ' . implode(' ', $hidden->zeroCounts);
        }
    }
    $lines[] = 'pruning';
    foreach ($result->pruning as $prune) {
        $lines[] = 'prune ' . $prune->percent . ' removed ' . $prune->removed . ' correct ' . $prune->correct
            . ' test_acc ' . ratio($prune->correct, $total) . ' test_loss ' . real($prune->loss, 6);
    }
    $lines[] = 'noise';
    foreach ($result->noise as $noise) {
        $lines[] = 'noise ' . $noise->rate . ' correct ' . $noise->correct . ' test_acc ' . ratio($noise->correct, $total);
    }
    $ids = array_map(fn($i) => $data->test[$i]->id, $result->misclassified);
    $lines[] = 'misclassified ' . count($ids) . ($ids ? ' ' . implode(' ', $ids) : '');
    return $lines;
}

function majorityVote(array $runs, array $ranked, object $data): object
{
    $predictions = [];
    $correct = 0;
    $fixed = 0;
    $broken = 0;
    foreach ($data->test as $i => $image) {
        $votes = array_fill(0, $data->classes, 0);
        foreach ($runs as $result) {
            $votes[$result->test->results[$i]->predicted]++;
        }
        $maximum = max($votes);
        foreach ($ranked as $result) {
            $chosen = $result->test->results[$i]->predicted;
            if ($votes[$chosen] === $maximum) {
                break;
            }
        }
        $predictions[] = $chosen;
        $matches = $chosen === $image->label;
        $topCorrect = $ranked[0]->test->results[$i]->correct;
        if ($matches) {
            $correct++;
        }
        if ($matches && !$topCorrect) {
            $fixed++;
        }
        if (!$matches && $topCorrect) {
            $broken++;
        }
    }
    return (object) ['predictions' => $predictions, 'correct' => $correct, 'fixed' => $fixed, 'broken' => $broken];
}

function softEnsemble(array $runs, object $data): ?object
{
    $selected = array_values(array_filter($runs, fn($result) => $result->network->outputType === 'SOFTMAX'));
    if (!$selected) {
        return null;
    }
    $correct = 0;
    foreach ($data->test as $i => $image) {
        $scores = array_fill(0, $data->classes, 0.0);
        foreach ($selected as $result) {
            for ($k = 0; $k < $data->classes; $k++) {
                $scores[$k] += $result->test->results[$i]->scores[$k];
            }
        }
        foreach ($scores as &$score) {
            $score /= count($selected);
        }
        unset($score);
        if (prediction($scores) === $image->label) {
            $correct++;
        }
    }
    return (object) ['runs' => count($selected), 'correct' => $correct];
}

function saliency(object $top, object $data): array
{
    $sums = array_fill(0, $data->classes, array_fill(0, $data->pixels, 0.0));
    $counts = array_fill(0, $data->classes, 0);
    foreach ($data->test as $i => $image) {
        $label = $image->label;
        $inputGradient = $top->network->backward($top->theta, $top->test->results[$i])->inputGradient;
        $counts[$label]++;
        for ($p = 0; $p < $data->pixels; $p++) {
            $sums[$label][$p] += abs($inputGradient[$p]);
        }
    }
    $maps = [];
    for ($k = 0; $k < $data->classes; $k++) {
        if ($counts[$k] === 0) {
            $maps[] = array_fill(0, $data->pixels, 0);
            continue;
        }
        $means = array_map(fn($value) => $value / $counts[$k], $sums[$k]);
        $maximum = max($means);
        $maps[] = array_map(fn($value) => $maximum == 0.0 ? 0 : min(9, (int) floor(10 * $value / $maximum)), $means);
    }
    return $maps;
}

function nearestImage(object $image, array $candidates): object
{
    $nearest = null;
    $distance = PHP_INT_MAX;
    foreach ($candidates as $candidate) {
        $differences = 0;
        for ($p = 0; $p < strlen($image->pixels); $p++) {
            if ($image->pixels[$p] !== $candidate->pixels[$p]) {
                $differences++;
            }
        }
        if ($differences < $distance) {
            $nearest = $candidate;
            $distance = $differences;
        }
    }
    return (object) ['image' => $nearest, 'distance' => $distance];
}

function comparisonReport(array $runs, object $data, array $noisy): array
{
    $ranked = $runs;
    usort($ranked, fn($a, $b) => ($b->test->correct <=> $a->test->correct)
        ?: ($a->best->loss <=> $b->best->loss) ?: ($a->run->order <=> $b->run->order));
    $top = $ranked[0];
    $total = count($data->test);
    $ensemble = majorityVote($runs, $ranked, $data);
    $soft = softEnsemble($runs, $data);
    $lines = ['comparison'];
    foreach ($ranked as $i => $result) {
        $lines[] = 'rank ' . ($i + 1) . ' ' . $result->run->name . ' correct ' . $result->test->correct
            . ' test_acc ' . ratio($result->test->correct, $total) . ' best_val_loss ' . real($result->best->loss, 6)
            . ' test_loss ' . real($result->test->loss, 6) . ' best_epoch ' . $result->best->epoch
            . ' epochs ' . $result->epochs . ' updates ' . $result->updates;
    }
    $lines[] = 'agreement';
    foreach ($runs as $left) {
        $agreements = [];
        foreach ($runs as $right) {
            $count = 0;
            for ($i = 0; $i < $total; $i++) {
                if ($left->test->results[$i]->predicted === $right->test->results[$i]->predicted) {
                    $count++;
                }
            }
            $agreements[] = $count;
        }
        $lines[] = $left->run->name . ' ' . implode(' ', $agreements);
    }
    $lines[] = 'mcnemar ' . $top->run->name;
    foreach (array_slice($ranked, 1) as $other) {
        $b = 0;
        $c = 0;
        for ($i = 0; $i < $total; $i++) {
            if ($top->test->results[$i]->correct && !$other->test->results[$i]->correct) {
                $b++;
            }
            if (!$top->test->results[$i]->correct && $other->test->results[$i]->correct) {
                $c++;
            }
        }
        $difference = max(abs($b - $c) - 1, 0);
        $numerator = $difference * $difference;
        $denominator = $b + $c;
        $chi = $denominator === 0 ? '0.0000' : ratio($numerator, $denominator);
        $significant = $numerator * 1000 > 3841 * $denominator;
        $lines[] = 'vs ' . $other->run->name . ' b ' . $b . ' c ' . $c . ' chi2 ' . $chi
            . ' significant ' . ($significant ? 'yes' : 'no');
    }
    $lines[] = 'ensemble correct ' . $ensemble->correct . '/' . $total . ' test_acc ' . ratio($ensemble->correct, $total)
        . ' fixed ' . $ensemble->fixed . ' broken ' . $ensemble->broken;
    $lines[] = $soft === null ? 'soft_ensemble none' : 'soft_ensemble runs ' . $soft->runs . ' correct ' . $soft->correct
        . '/' . $total . ' test_acc ' . ratio($soft->correct, $total);
    foreach ($noisy as $group) {
        $lines[] = 'noise ' . $group->rate . ' flipped ' . $group->flipped;
    }
    $pairs = [];
    for ($y = 0; $y < $data->classes; $y++) {
        for ($p = 0; $p < $data->classes; $p++) {
            if ($y === $p) {
                continue;
            }
            $count = 0;
            foreach ($runs as $result) {
                $count += $result->matrix[$y][$p];
            }
            if ($count > 0) {
                $pairs[] = (object) ['y' => $y, 'p' => $p, 'count' => $count];
            }
        }
    }
    usort($pairs, fn($a, $b) => ($b->count <=> $a->count) ?: ($a->y <=> $b->y) ?: ($a->p <=> $b->p));
    $lines[] = 'confused_pairs';
    foreach (array_slice($pairs, 0, 5) as $pair) {
        $lines[] = $pair->y . ' as ' . $pair->p . ' count ' . $pair->count;
    }
    $lines[] = '';
    $lines[] = 'saliency ' . $top->run->name;
    $lines[] = 'classes ' . implode(' ', range(0, $data->classes - 1));
    array_push($lines, ...levelMaps(saliency($top, $data), $data->width, $data->height));
    $training = evaluate($top->network, $top->theta, $data->train);
    $hardest = [];
    foreach ($training->results as $i => $result) {
        $hardest[] = (object) ['result' => $result, 'image' => $data->train[$i], 'order' => $i];
    }
    usort($hardest, fn($a, $b) => ($b->result->loss <=> $a->result->loss) ?: ($a->order <=> $b->order));
    $lines[] = '';
    $lines[] = 'hardest_training_examples ' . $top->run->name;
    foreach (array_slice($hardest, 0, 5) as $item) {
        $lines[] = $item->image->id . ' label ' . $item->image->label . ' predicted ' . $item->result->predicted
            . ' loss ' . real($item->result->loss, 6);
    }
    $lines[] = '';
    $lines[] = 'misclassified_examples ' . $top->run->name;
    foreach ($top->misclassified as $i) {
        $image = $data->test[$i];
        $result = $top->test->results[$i];
        $nearest = nearestImage($image, $data->allTrain);
        $predictions = array_map(fn($run) => $run->test->results[$i]->predicted, $runs);
        $lines[] = $image->id . ' label ' . $image->label . ' predicted ' . $result->predicted
            . ' confidence ' . real($result->confidence) . ' true_score ' . real($result->scores[$image->label])
            . ' runs ' . implode(' ', $predictions) . ' ensemble ' . $ensemble->predictions[$i];
        $lines[] = 'nearest ' . $nearest->image->id . ' label ' . $nearest->image->label . ' distance ' . $nearest->distance;
        array_push($lines, ...imageRows($image, $data->width, $data->height));
    }
    return $lines;
}

function trainingLog(array $runs, object $data): array
{
    $lines = ['run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved'];
    foreach ($runs as $result) {
        foreach ($result->history as $epoch) {
            $lines[] = implode(',', [$result->run->name, $epoch->epoch, real($epoch->rate, 6), real($epoch->magnitude),
                real($epoch->trainLoss, 6), ratio($epoch->trainCorrect, count($data->train)), real($epoch->validationLoss, 6),
                ratio($epoch->validationCorrect, count($data->validation)), $epoch->improved ? 1 : 0]);
        }
    }
    return $lines;
}

function finalWeightLines(array $runs): array
{
    $lines = [];
    foreach ($runs as $result) {
        if ($lines) {
            $lines[] = '';
        }
        $lines[] = 'RUN ' . $result->run->name . ' NETWORK ' . $result->network->name . ' EPOCH ' . $result->best->epoch;
        foreach ($result->network->layers as $l => $layer) {
            $lines[] = 'LAYER ' . ($l + 1) . ' ' . $layer->units . ' ' . $layer->inputs;
            for ($j = 0; $j < $layer->units; $j++) {
                $offset = $layer->offset + $j * $layer->inputs;
                $values = array_slice($result->theta, $offset, $layer->inputs);
                $lines[] = 'W ' . implode(' ', array_map(fn($value) => real($value), $values));
            }
            $values = array_slice($result->theta, $layer->biasOffset, $layer->units);
            $lines[] = 'B ' . implode(' ', array_map(fn($value) => real($value), $values));
        }
    }
    return $lines;
}

function main(): void
{
    $input = readInputs();
    $networks = [];
    $networkByName = [];
    foreach ($input->networks as $definition) {
        $network = new Network($definition, $input->width * $input->height, $input->weights['#' . $definition->name]);
        $networks[] = $network;
        $networkByName['#' . $definition->name] = $network;
    }
    $validationSize = intdiv(count($input->train), 5);
    $trainingSize = count($input->train) - $validationSize;
    $data = (object) ['width' => $input->width, 'height' => $input->height, 'pixels' => $input->width * $input->height,
        'classes' => $networks[0]->classes, 'allTrain' => $input->train, 'train' => array_slice($input->train, 0, $trainingSize),
        'validation' => array_slice($input->train, $trainingSize), 'test' => $input->test];
    $checkLines = [];
    foreach ($networks as $network) {
        if ($checkLines) {
            $checkLines[] = '';
        }
        array_push($checkLines, ...checkNetwork($network, $data, $input->settings));
    }
    $noisy = [];
    foreach ($input->settings->noise as $rate) {
        $noisy[] = noisyData($data->test, $rate, $input->settings->seed);
    }
    $runs = [];
    foreach ($input->settings->runs as $run) {
        $network = $networkByName['#' . $run->network];
        $runs[] = evaluateRun(trainRun($run, $network, $data, $input->settings), $data, $input->settings, $noisy);
    }
    $predictions = ['run,id,label,predicted,confidence'];
    $report = dataReport($data);
    foreach ($runs as $result) {
        foreach ($result->test->results as $i => $prediction) {
            $predictions[] = implode(',', [$result->run->name, $data->test[$i]->id, $data->test[$i]->label,
                $prediction->predicted, real($prediction->confidence)]);
        }
        $report[] = '';
        array_push($report, ...runReport($result, $data));
    }
    $report[] = '';
    array_push($report, ...comparisonReport($runs, $data, $noisy));
    $outputs = ['gradient_check.txt' => $checkLines, 'training_log.csv' => trainingLog($runs, $data),
        'final_weights.txt' => finalWeightLines($runs), 'predictions.csv' => $predictions, 'evaluation.txt' => $report];
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    foreach ($outputs as $filename => $lines) {
        file_put_contents('output/' . $filename, implode("\n", $lines) . "\n");
    }
}

main();
