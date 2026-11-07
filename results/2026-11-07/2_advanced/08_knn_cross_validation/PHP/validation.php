<?php
final class Model {
    public function __construct(public int $k, public string $metric, public string $weighting, public string $scaling) {}
    public function notation(): string { return "k={$this->k} metric={$this->metric} weighting={$this->weighting} scaling={$this->scaling}"; }
}
function stratifiedFolds(array $rows, int $count): array {
    $ordered = array_keys($rows);
    usort($ordered, fn($a, $b) => strcmp($rows[$a]->label, $rows[$b]->label) ?: strcmp($rows[$a]->id, $rows[$b]->id));
    $folds = array_fill(0, $count, []); foreach ($ordered as $position => $index) $folds[$position % $count][] = $index;
    foreach ($folds as &$fold) sort($fold, SORT_NUMERIC); unset($fold); return $folds;
}
function trainingRows(array $rows, array $fold): array {
    $excluded = array_fill_keys($fold, true); return array_values(array_filter($rows, fn($row, $j) => !isset($excluded[$j]), ARRAY_FILTER_USE_BOTH));
}
function neighborOrders(array $training, array $queries, string $method, string $metric, array $features): array {
    $scaling = new Scaling($training, $method); $references = [];
    foreach ($training as $row) $references[] = [$scaling->transform($row->values, $features), $row];
    $orders = [];
    foreach ($queries as $query) {
        $vector = $scaling->transform($query->values, $features); $neighbors = [];
        foreach ($references as [$reference, $row]) $neighbors[] = [distance($vector, $reference, $metric), $row];
        $orders[] = sortNeighbors($neighbors);
    }
    return $orders;
}
function predictRows(Model $model, array $training, array $queries, array $features): array {
    return array_map(fn($order) => new Prediction(array_slice($order, 0, $model->k), $model->weighting), neighborOrders($training, $queries, $model->scaling, $model->metric, $features));
}
function rootMeanSquare(array $errors): float {
    $sum = 0.0; foreach ($errors as $error) $sum += $error * $error; return sqrt($sum / count($errors));
}
function meanAbsolute(array $errors): float {
    $sum = 0.0; foreach ($errors as $error) $sum += abs($error); return $sum / count($errors);
}
function rSquared(array $errors, array $targets): float {
    $sum = 0.0; foreach ($targets as $target) $sum += $target; $mean = $sum / count($targets);
    $residual = 0.0; foreach ($errors as $error) $residual += $error * $error;
    $spread = 0.0; foreach ($targets as $target) { $difference = $target - $mean; $spread += $difference * $difference; }
    return 1 - $residual / $spread;
}
function correctCount(array $predictions, array $rows): int {
    $correct = 0; foreach ($rows as $j => $row) if ($predictions[$j]->label === $row->label) $correct++; return $correct;
}
final class CrossValidation {
    public int $correct = 0;
    public float $rmse;
    public array $hits = [];
    public function __construct(public Model $model, array $rows, public array $predictions) {
        $errors = []; foreach ($rows as $j => $row) { $hit = $predictions[$j]->label === $row->label; $this->hits[] = $hit; $this->correct += (int)$hit; $errors[] = $predictions[$j]->estimate - $row->target; }
        $this->rmse = rootMeanSquare($errors);
    }
}
function crossValidate(array $models, array $rows, int $count, array $features): array {
    $predictions = array_fill(0, count($models), array_fill(0, count($rows), null)); $spaces = [];
    foreach ($models as $j => $model) $spaces[$model->scaling . '|' . $model->metric][] = $j;
    foreach (stratifiedFolds($rows, $count) as $fold) {
        $training = trainingRows($rows, $fold); $queries = array_map(fn($j) => $rows[$j], $fold);
        foreach ($spaces as $indices) {
            $first = $models[$indices[0]]; $orders = neighborOrders($training, $queries, $first->scaling, $first->metric, $features);
            foreach ($indices as $j) foreach ($fold as $position => $index) $predictions[$j][$index] = new Prediction(array_slice($orders[$position], 0, $models[$j]->k), $models[$j]->weighting, false);
        }
    }
    $results = []; foreach ($models as $j => $model) $results[] = new CrossValidation($model, $rows, $predictions[$j]); return $results;
}
function bestClassifier(array $results): CrossValidation {
    $best = $results[0]; foreach ($results as $result) if ($result->correct > $best->correct) $best = $result; return $best;
}
function bestRegressor(array $results): CrossValidation {
    $best = $results[0]; foreach ($results as $result) if (fourDecimal($result->rmse) < fourDecimal($best->rmse)) $best = $result; return $best;
}
