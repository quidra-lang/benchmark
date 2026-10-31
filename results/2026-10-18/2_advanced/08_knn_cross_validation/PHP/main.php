<?php
require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/scaling.php';
require_once __DIR__ . '/neighbors.php';
require_once __DIR__ . '/validation.php';
require_once __DIR__ . '/report.php';

function idOrder(array $rows): array { usort($rows, fn($a, $b) => strcmp($a->id, $b->id)); return $rows; }
function labelCounts(array $rows, array $labels): string {
    $counts = array_fill_keys($labels, 0); foreach ($rows as $row) $counts[$row->label]++;
    $parts = []; foreach ($labels as $label) { $parts[] = $label; $parts[] = $counts[$label]; } return implode(' ', $parts);
}
function evaluationLines(array $pairs, array $labels): array {
    $matrix = []; foreach ($labels as $label) $matrix[$label] = array_fill_keys($labels, 0);
    foreach ($pairs as [$truth, $predicted]) $matrix[$truth][$predicted]++;
    $lines = ['true\\predicted ' . implode(' ', $labels)]; $totals = [0.0, 0.0, 0.0]; $valued = [0, 0, 0];
    foreach ($labels as $label) $lines[] = $label . ' ' . implode(' ', $matrix[$label]);
    foreach ($labels as $label) {
        $hits = $matrix[$label][$label]; $predicted = 0; $actual = 0;
        foreach ($labels as $other) { $predicted += $matrix[$other][$label]; $actual += $matrix[$label][$other]; }
        foreach ([[$hits, $predicted], [$hits, $actual], [2 * $hits, $predicted + $actual]] as $j => [$a, $b]) if ($b > 0) { $totals[$j] += $a / $b; $valued[$j]++; }
        $lines[] = "class $label precision " . fraction($hits, $predicted) . ' recall ' . fraction($hits, $actual) . ' f1 ' . fraction(2 * $hits, $predicted + $actual) . " support $actual";
    }
    $averages = []; foreach ($totals as $j => $sum) $averages[] = $valued[$j] ? fixed($sum / $valued[$j]) : '-';
    $lines[] = "macro precision {$averages[0]} recall {$averages[1]} f1 {$averages[2]}"; return $lines;
}
function reliabilityLines(array $pairs, array $bounds): array {
    $lowers = array_merge([0.0], $bounds); $counts = $hits = array_fill(0, count($lowers), 0); $shares = array_fill(0, count($lowers), 0.0);
    foreach ($pairs as [$prediction, $truth]) {
        $j = 0; foreach ($bounds as $bound) if ($bound <= $prediction->share) $j++;
        $counts[$j]++; if ($prediction->label === $truth) $hits[$j]++; $shares[$j] += $prediction->share;
    }
    $lines = []; foreach ($lowers as $j => $lower) {
        $text = 'bin ' . fixed($lower, 2) . " rows {$counts[$j]}";
        if ($counts[$j]) $text .= ' correct ' . ratio($hits[$j], $counts[$j]) . ' share ' . fixed($shares[$j] / $counts[$j]);
        $lines[] = $text;
    }
    return $lines;
}
final class ClassifierSpace {
    private array $distances = [];
    public function __construct(public Model $model, array $train, array $test) {
        $scaling = new Scaling($train, $model->scaling); $features = range(0, count($train[0]->values) - 1); $references = [];
        foreach ($train as $row) $references[] = $scaling->transform($row->values, $features);
        foreach (array_merge($train, $test) as $query) {
            $vector = $scaling->transform($query->values, $features); $gaps = [];
            foreach ($train as $j => $row) $gaps[$row->id] = distance($vector, $references[$j], $model->metric);
            $this->distances[$query->id] = $gaps;
        }
    }
    public function order(DataRow $query, array $rows): array {
        $gaps = $this->distances[$query->id]; return sortNeighbors(array_map(fn($row) => [$gaps[$row->id], $row], $rows));
    }
    public function vote(DataRow $query, array $rows, int $k): Prediction { return new Prediction(array_slice($this->order($query, $rows), 0, $k), $this->model->weighting, false); }
    public function nearestLabel(DataRow $query, array $rows): string { return $this->order($query, $rows)[0][1]->label; }
}
function wilsonEditing(ClassifierSpace $space, array $rows, int $k): array {
    $passes = [];
    while (true) {
        $removals = []; $removed = [];
        foreach ($rows as $row) {
            $others = array_values(array_filter($rows, fn($other) => $other !== $row)); $prediction = $space->vote($row, $others, $k);
            if ($prediction->label !== $row->label) { $removals[] = [$row, $prediction]; $removed[$row->id] = true; }
        }
        $passes[] = $removals; if (!$removals) return [$rows, $passes];
        $rows = array_values(array_filter($rows, fn($row) => !isset($removed[$row->id])));
    }
}
function hartCondensing(ClassifierSpace $space, array $rows): array {
    $store = [$rows[0]]; $stored = [$rows[0]->id => true]; $scans = 0;
    do {
        $scans++; $added = false;
        foreach ($rows as $row) if (!isset($stored[$row->id]) && $space->nearestLabel($row, $store) !== $row->label) { $store[] = $row; $stored[$row->id] = true; $added = true; }
    } while ($added);
    return [idOrder($store), $scans];
}
final class Experiment {
    private array $features, $labels, $labelled, $targeted, $grid = [], $folds, $results, $testPredictions, $testEstimates, $labelledPredictions = [];
    private CrossValidation $classifier, $regressor;
    public function __construct(private array $featureNames, private array $train, private array $test, private Settings $settings) {
        $this->features = range(0, count($featureNames) - 1); $this->labels = array_values(array_unique(array_map(fn($row) => $row->label, $train))); sort($this->labels, SORT_STRING);
        $this->labelled = array_values(array_filter($test, fn($row) => $row->label !== null)); $this->targeted = array_values(array_filter($test, fn($row) => $row->target !== null));
        foreach ($settings->kValues as $k) foreach ($settings->metrics as $metric) foreach ($settings->weightings as $weighting) foreach ($settings->scalings as $scaling) $this->grid[] = new Model($k, $metric, $weighting, $scaling);
        $this->folds = stratifiedFolds($train, $settings->folds); $this->results = crossValidate($this->grid, $train, $settings->folds, $this->features);
        $this->classifier = bestClassifier($this->results); $this->regressor = bestRegressor($this->results);
        $this->testPredictions = predictRows($this->classifier->model, $train, $test, $this->features);
        $this->testEstimates = array_map(fn($prediction) => $prediction->estimate, predictRows($this->regressor->model, $train, $test, $this->features));
        foreach ($test as $j => $row) if ($row->label !== null) $this->labelledPredictions[] = [$row, $this->testPredictions[$j]];
    }
    private function names(array $features): string { return implode(' ', array_map(fn($j) => $this->featureNames[$j], $features)); }
    private function trainRatio(int $count): string { return ratio($count, count($this->train)); }
    private function classifierSummary(CrossValidation $result): string { return $result->model->notation() . ' correct ' . $this->trainRatio($result->correct) . ' rmse ' . fixed($result->rmse); }
    private function regressorSummary(CrossValidation $result): string { return $result->model->notation() . ' rmse ' . fixed($result->rmse) . ' correct ' . $this->trainRatio($result->correct); }
    public function gridTable(): array {
        $lines = ['k,metric,weighting,scaling,correct,accuracy,rmse']; foreach ($this->results as $result) {
            $m = $result->model; $lines[] = implode(',', [$m->k, $m->metric, $m->weighting, $m->scaling, $result->correct, fixed($result->correct / count($this->train)), fixed($result->rmse)]);
        } return $lines;
    }
    public function predictionTable(): array {
        $lines = ['id,label,vote_share,estimate']; foreach ($this->test as $j => $row) {
            $p = $this->testPredictions[$j]; $lines[] = implode(',', [$row->id, $p->label, fixed($p->share), fixed($this->testEstimates[$j])]);
        } return $lines;
    }
    private function dataPart(): array {
        return ['data train ' . count($this->train) . ' test ' . count($this->test) . ' labelled ' . count($this->labelled) . ' targets ' . count($this->targeted) . ' features ' . count($this->features) . ' classes ' . count($this->labels), 'classes ' . labelCounts($this->train, $this->labels)];
    }
    private function scalingPart(string $method): array {
        $scaling = new Scaling($this->train, $method); $lines = ["scaling $method"];
        foreach ($this->featureNames as $j => $name) $lines[] = "$name center " . fixed($scaling->centers[$j], 6) . ' scale ' . fixed($scaling->scales[$j], 6); return $lines;
    }
    private function foldsPart(): array {
        $lines = ['folds ' . $this->settings->folds]; foreach ($this->folds as $j => $fold) $lines[] = 'fold ' . ($j + 1) . ' size ' . count($fold) . ' ' . labelCounts(array_map(fn($index) => $this->train[$index], $fold), $this->labels); return $lines;
    }
    private function topPart(bool $accuracy): array {
        $ranking = array_keys($this->results);
        usort($ranking, fn($a, $b) => ($accuracy ? ($this->results[$b]->correct <=> $this->results[$a]->correct) : (fourDecimal($this->results[$a]->rmse) <=> fourDecimal($this->results[$b]->rmse))) ?: ($a <=> $b));
        $lines = ['top ' . $this->settings->top . ' by ' . ($accuracy ? 'accuracy' : 'rmse')];
        foreach (array_slice($ranking, 0, $this->settings->top) as $j => $index) $lines[] = ($j + 1) . ' ' . ($accuracy ? $this->classifierSummary($this->results[$index]) : $this->regressorSummary($this->results[$index])); return $lines;
    }
    private function bestPerParts(): array {
        $parts = []; foreach (['k' => $this->settings->kValues, 'metric' => $this->settings->metrics, 'weighting' => $this->settings->weightings, 'scaling' => $this->settings->scalings] as $item => $values) {
            $lines = ["best per $item"]; foreach ($values as $value) {
                $group = array_values(array_filter($this->results, fn($r) => $r->model->$item === $value)); $cl = bestClassifier($group); $reg = bestRegressor($group);
                $lines[] = "$item=$value classifier " . $cl->model->notation() . ' accuracy ' . fixed($cl->correct / count($this->train)) . ' regressor ' . $reg->model->notation() . ' rmse ' . fixed($reg->rmse);
            } $parts[] = $lines;
        } return $parts;
    }
    private function modelFoldParts(): array {
        $classifier = ['classifier folds']; $regressor = ['regressor folds']; foreach ($this->folds as $j => $fold) {
            $correct = 0; $errors = []; foreach ($fold as $index) { $correct += (int)$this->classifier->hits[$index]; $errors[] = $this->regressor->predictions[$index]->estimate - $this->train[$index]->target; }
            $classifier[] = 'fold ' . ($j + 1) . ' correct ' . ratio($correct, count($fold)); $regressor[] = 'fold ' . ($j + 1) . ' size ' . count($fold) . ' rmse ' . fixed(rootMeanSquare($errors));
        } return [$classifier, $regressor];
    }
    private function mcnemarPart(): array {
        $lines = ['mcnemar']; foreach ($this->settings->metrics as $metric) {
            $comparison = bestClassifier(array_values(array_filter($this->results, fn($r) => $r->model->metric === $metric))); $b = 0; $c = 0;
            foreach ($this->classifier->hits as $j => $hit) { if ($hit && !$comparison->hits[$j]) $b++; elseif (!$hit && $comparison->hits[$j]) $c++; }
            $disagreements = $b + $c; $difference = max(0, abs($b - $c) - 1); $u = $difference * $difference;
            $lines[] = $comparison->model->notation() . " b $b c $c statistic " . ($disagreements ? fraction($u, $disagreements) : '0/1 0.0000') . ' significant ' . (1000 * $u > 3841 * $disagreements ? 'yes' : 'no');
        } return $lines;
    }
    private function leaveOneOutParts(): array {
        $model = $this->classifier->model; $byK = array_fill_keys($this->settings->kValues, []); $estimates = [];
        foreach ($this->train as $index => $row) {
            $others = trainingRows($this->train, [$index]); $order = neighborOrders($others, [$row], $model->scaling, $model->metric, $this->features)[0];
            foreach ($this->settings->kValues as $k) $byK[$k][] = new Prediction(array_slice($order, 0, $k), $model->weighting, false);
            $estimates[] = predictRows($this->regressor->model, $others, [$row], $this->features)[0]->estimate;
        }
        $errors = []; $classErrors = array_fill_keys($this->labels, 0); $predictions = $byK[$model->k];
        foreach ($this->train as $j => $row) if ($predictions[$j]->label !== $row->label) { $errors[] = [$row, $predictions[$j]]; $classErrors[$row->label]++; }
        $classListing = []; foreach ($this->labels as $label) { $classListing[] = $label; $classListing[] = $classErrors[$label]; }
        $cl = ['leave_one_out classifier ' . $model->notation(), 'errors ' . $this->trainRatio(count($errors)), 'class_errors ' . implode(' ', $classListing)];
        usort($errors, fn($a, $b) => strcmp($a[0]->id, $b[0]->id)); foreach ($errors as [$row, $p]) $cl[] = "$row->id true $row->label predicted $p->label share " . fixed($p->share);
        $residuals = []; foreach ($this->train as $j => $row) $residuals[] = $estimates[$j] - $row->target;
        $reg = ['leave_one_out regressor ' . $this->regressor->model->notation(), 'rmse ' . fixed(rootMeanSquare($residuals)) . ' mae ' . fixed(meanAbsolute($residuals)), 'largest ' . $this->settings->top . ' residuals'];
        $ranking = array_keys($this->train); usort($ranking, fn($a, $b) => (fourDecimal(abs($residuals[$b])) <=> fourDecimal(abs($residuals[$a]))) ?: strcmp($this->train[$a]->id, $this->train[$b]->id));
        foreach (array_slice($ranking, 0, $this->settings->top) as $j) { $row = $this->train[$j]; $reg[] = "$row->id target " . fixed($row->target) . ' estimate ' . fixed($estimates[$j]) . ' residual ' . fixed($residuals[$j]); }
        $by = ["leave_one_out by k metric=$model->metric weighting=$model->weighting scaling=$model->scaling"];
        foreach ($this->settings->kValues as $k) { $residuals = []; foreach ($this->train as $j => $row) $residuals[] = $byK[$k][$j]->estimate - $row->target; $by[] = "k=$k correct " . $this->trainRatio(correctCount($byK[$k], $this->train)) . ' rmse ' . fixed(rootMeanSquare($residuals)); }
        return [$cl, $reg, $by];
    }
    private function nestedPart(): array {
        $lines = ['nested_cross_validation folds ' . $this->settings->folds]; $estimates = array_fill(0, count($this->train), 0.0); $total = 0;
        foreach ($this->folds as $j => $fold) {
            $inner = trainingRows($this->train, $fold); $queries = array_map(fn($index) => $this->train[$index], $fold); $results = crossValidate($this->grid, $inner, $this->settings->folds, $this->features);
            $cl = bestClassifier($results); $reg = bestRegressor($results); $correct = correctCount(predictRows($cl->model, $inner, $queries, $this->features), $queries); $total += $correct;
            $predictions = predictRows($reg->model, $inner, $queries, $this->features); $errors = [];
            foreach ($fold as $position => $index) { $estimates[$index] = $predictions[$position]->estimate; $errors[] = $estimates[$index] - $this->train[$index]->target; }
            $lines[] = 'fold ' . ($j + 1) . ' classifier ' . $cl->model->notation() . ' inner ' . fixed($cl->correct / count($inner)) . ' outer ' . ratio($correct, count($fold));
            $lines[] = 'fold ' . ($j + 1) . ' regressor ' . $reg->model->notation() . ' inner ' . fixed($reg->rmse) . ' outer ' . fixed(rootMeanSquare($errors));
        }
        $errors = []; foreach ($this->train as $j => $row) $errors[] = $estimates[$j] - $row->target; $lines[] = 'nested accuracy ' . $this->trainRatio($total) . ' rmse ' . fixed(rootMeanSquare($errors)); return $lines;
    }
    private function featurePart(): array {
        $model = $this->classifier->model; $current = $selected = $this->features; $selectedCorrect = $this->classifier->correct; $step = 0;
        $lines = ['feature_selection ' . $model->notation(), 'start features ' . $this->names($current) . ' correct ' . $this->trainRatio($selectedCorrect)];
        while (count($current) >= 3) {
            $step++; $candidates = []; $removed = $current[0]; $correct = -1;
            foreach ($current as $feature) {
                $remaining = array_values(array_filter($current, fn($other) => $other !== $feature)); $result = crossValidate([$model], $this->train, $this->settings->folds, $remaining)[0];
                $candidates[] = $this->featureNames[$feature]; $candidates[] = $result->correct; if ($result->correct > $correct) { $correct = $result->correct; $removed = $feature; }
            }
            $current = array_values(array_filter($current, fn($other) => $other !== $removed));
            $lines[] = "step $step remove {$this->featureNames[$removed]} correct " . $this->trainRatio($correct) . ' candidates ' . implode(' ', $candidates);
            if ($correct >= $selectedCorrect) { $selected = $current; $selectedCorrect = $correct; }
        }
        $predictions = predictRows($model, $this->train, $this->labelled, $selected);
        $lines[] = 'selected features ' . $this->names($selected) . ' correct ' . $this->trainRatio($selectedCorrect); $lines[] = 'selected test ' . ratio(correctCount($predictions, $this->labelled), count($this->labelled)); return $lines;
    }
    private function uncertainPart(): array {
        $margins = array_map(fn($p) => $p->share - $p->runnerShare, $this->testPredictions); $ranking = array_keys($this->test);
        usort($ranking, fn($a, $b) => (fourDecimal($margins[$a]) <=> fourDecimal($margins[$b])) ?: ($a <=> $b)); $lines = ['uncertain ' . $this->settings->top . ' test rows'];
        foreach (array_slice($ranking, 0, $this->settings->top) as $j) { $row = $this->test[$j]; $p = $this->testPredictions[$j]; $lines[] = "$row->id predicted $p->label share " . fixed($p->share) . ' runner_up ' . ($p->runner ?? '-') . ' share ' . fixed($p->runnerShare) . ' margin ' . fixed($margins[$j]) . ' true ' . ($row->label ?? '-'); } return $lines;
    }
    private function regressionPart(): array {
        $errors = []; $targets = []; $classErrors = array_fill_keys($this->labels, []);
        foreach ($this->test as $j => $row) if ($row->target !== null) { $error = $this->testEstimates[$j] - $row->target; $errors[] = $error; $targets[] = $row->target; if ($row->label !== null) $classErrors[$row->label][] = $error; }
        $lines = ['test regression ' . $this->regressor->model->notation(), 'targets ' . count($errors) . ' rmse ' . fixed(rootMeanSquare($errors)) . ' mae ' . fixed(meanAbsolute($errors)) . ' r2 ' . fixed(rSquared($errors, $targets))];
        foreach ($this->labels as $label) { $found = $classErrors[$label]; $lines[] = "class $label targets " . count($found) . ' rmse ' . ($found ? fixed(rootMeanSquare($found)) : '-'); } return $lines;
    }
    private function misclassifiedPart(): array {
        $lines = ['misclassified test rows']; $count = 0;
        foreach ($this->labelledPredictions as [$row, $p]) if ($row->label !== $p->label) { $count++; $lines[] = "$row->id true $row->label predicted $p->label share " . fixed($p->share); foreach ($p->neighbors as [$gap, $neighbor]) $lines[] = "  $neighbor->id $neighbor->label " . fixed($gap); }
        $lines[] = "count $count"; return $lines;
    }
    public function metricsReport(): array {
        $parts = [$this->dataPart()]; foreach ($this->settings->scalings as $method) $parts[] = $this->scalingPart($method);
        $parts[] = $this->foldsPart(); $parts[] = ['grid ' . count($this->grid), 'best_classifier ' . $this->classifierSummary($this->classifier), 'best_regressor ' . $this->regressorSummary($this->regressor)];
        $parts[] = $this->topPart(true); $parts[] = $this->topPart(false); array_push($parts, ...$this->bestPerParts(), ...$this->modelFoldParts());
        $pairs = []; $shares = []; foreach ($this->train as $j => $row) { $p = $this->classifier->predictions[$j]; $pairs[] = [$row->label, $p->label]; $shares[] = [$p, $row->label]; }
        $parts[] = array_merge(['cross_validation classes'], evaluationLines($pairs, $this->labels)); $parts[] = array_merge(['cross_validation reliability'], reliabilityLines($shares, $this->settings->bins));
        $parts[] = $this->mcnemarPart(); array_push($parts, ...$this->leaveOneOutParts()); $parts[] = $this->nestedPart(); $parts[] = $this->featurePart();
        $pairs = []; $shares = []; $correct = 0; foreach ($this->labelledPredictions as [$row, $p]) { $pairs[] = [$row->label, $p->label]; $shares[] = [$p, $row->label]; if ($row->label === $p->label) $correct++; }
        $parts[] = array_merge(['test classification ' . $this->classifier->model->notation(), 'labelled ' . count($pairs) . ' correct ' . ratio($correct, count($pairs))], evaluationLines($pairs, $this->labels));
        $parts[] = array_merge(['test reliability'], reliabilityLines($shares, $this->settings->bins)); $parts[] = $this->uncertainPart(); $parts[] = $this->regressionPart(); $parts[] = $this->misclassifiedPart(); return joinParts($parts);
    }
    public function learningCurveTable(): array {
        $lines = ['n,train_size,correct,accuracy,rmse']; foreach ($this->settings->curve as $limit) {
            $taken = array_fill_keys($this->labels, 0); $rows = []; foreach ($this->train as $row) if ($taken[$row->label] < $limit) { $taken[$row->label]++; $rows[] = $row; }
            $correct = correctCount(predictRows($this->classifier->model, $rows, $this->labelled, $this->features), $this->labelled); $predictions = predictRows($this->regressor->model, $rows, $this->targeted, $this->features); $errors = [];
            foreach ($this->targeted as $j => $row) $errors[] = $predictions[$j]->estimate - $row->target;
            $lines[] = implode(',', [$limit, count($rows), $correct, fixed($correct / count($this->labelled)), fixed(rootMeanSquare($errors))]);
        } return $lines;
    }
    private function prototypeLine(ClassifierSpace $space, string $name, array $rows): string {
        $knn = 0; $nearest = 0; foreach ($this->labelled as $row) { if ($space->vote($row, $rows, $this->classifier->model->k)->label === $row->label) $knn++; if ($space->nearestLabel($row, $rows) === $row->label) $nearest++; }
        return "set $name size " . count($rows) . ' ' . labelCounts($rows, $this->labels) . ' knn ' . ratio($knn, count($this->labelled)) . ' 1nn ' . ratio($nearest, count($this->labelled));
    }
    private function bordersPart(ClassifierSpace $space, array $ordered): array {
        $lines = ['borders']; $total = 0; foreach ($this->labels as $label) {
            $members = array_values(array_filter($ordered, fn($row) => $row->label === $label)); $borders = 0; $sameTotal = 0.0; $otherTotal = 0.0;
            foreach ($members as $row) {
                $order = $space->order($row, array_values(array_filter($ordered, fn($other) => $other !== $row))); $same = null; $other = null;
                foreach ($order as [$gap, $neighbor]) { if ($neighbor->label === $label && $same === null) $same = $gap; if ($neighbor->label !== $label && $other === null) $other = $gap; if ($same !== null && $other !== null) break; }
                if ($order[0][1]->label !== $label) $borders++; $sameTotal += $same; $otherTotal += $other;
            }
            $total += $borders; $lines[] = "class $label size " . count($members) . " border $borders same " . fixed($sameTotal / count($members)) . ' other ' . fixed($otherTotal / count($members));
        } $lines[] = 'border total ' . $this->trainRatio($total); return $lines;
    }
    private function hubsPart(): array {
        $occurrences = []; foreach ($this->train as $row) $occurrences[$row->id] = 0; foreach ($this->testPredictions as $p) foreach ($p->neighbors as [, $row]) $occurrences[$row->id]++;
        $ranked = $this->train; usort($ranked, fn($a, $b) => ($occurrences[$b->id] <=> $occurrences[$a->id]) ?: strcmp($a->id, $b->id));
        $lines = ['hubs k=' . $this->classifier->model->k . ' queries ' . count($this->test)]; foreach (array_slice($ranked, 0, $this->settings->top) as $row) $lines[] = "$row->id $row->label {$occurrences[$row->id]}";
        $lines[] = 'anti_hubs ' . count(array_filter($occurrences, fn($count) => $count === 0)); return $lines;
    }
    public function prototypesReport(): array {
        $space = new ClassifierSpace($this->classifier->model, $this->train, $this->test); $ordered = idOrder($this->train); [$edited, $passes] = wilsonEditing($space, $ordered, $this->settings->editK);
        [$condensed, $scans] = hartCondensing($space, $ordered); [$editedCondensed, $editedScans] = hartCondensing($space, $edited);
        $editing = ['editing k=' . $this->settings->editK]; foreach ($passes as $j => $removed) { $editing[] = 'pass ' . ($j + 1) . ' removed ' . count($removed); foreach ($removed as [$row, $p]) $editing[] = "  $row->id true $row->label predicted $p->label share " . fixed($p->share); }
        $editing[] = 'edited size ' . count($edited) . ' removed ' . (count($ordered) - count($edited)); $setLines = [];
        foreach (['original' => $ordered, 'edited' => $edited, 'condensed' => $condensed, 'edited_condensed' => $editedCondensed] as $name => $rows) $setLines[] = $this->prototypeLine($space, $name, $rows);
        $idLines = fn($rows) => array_map(fn($chunk) => implode(' ', array_map(fn($row) => $row->id, $chunk)), array_chunk($rows, 10));
        return joinParts([['space ' . $this->classifier->model->notation()], $editing, ["condensing original scans $scans size " . count($condensed), "condensing edited scans $editedScans size " . count($editedCondensed)], $setLines, array_merge(['prototypes condensed'], $idLines($condensed)), array_merge(['prototypes edited_condensed'], $idLines($editedCondensed)), $this->bordersPart($space, $ordered), $this->hubsPart()]);
    }
}
[$featureNames, $train] = readRows('train.csv'); [, $test] = readRows('test.csv'); $experiment = new Experiment($featureNames, $train, $test, new Settings('input/params.txt'));
if (!is_dir('output')) mkdir('output');
writeLines('cv_grid.csv', $experiment->gridTable()); writeLines('predictions.csv', $experiment->predictionTable()); writeLines('metrics.txt', $experiment->metricsReport());
writeLines('learning_curve.csv', $experiment->learningCurveTable()); writeLines('prototypes.txt', $experiment->prototypesReport());
