<?php

require_once __DIR__ . '/logistic.php';

function softmaxRow(array $weights, array $vector, int $label = 0): object
{
    $scores = array_map(fn($row) => score($row, $vector), $weights);
    $maximum = max($scores);
    $shifted = array_map(fn($value) => $value - $maximum, $scores);
    $exponentials = array_map('exp', $shifted);
    $total = 0.0;
    foreach ($exponentials as $value) {
        $total += $value;
    }
    $probabilities = array_map(fn($value) => $value / $total, $exponentials);
    $predicted = 0;
    for ($index = 1; $index < count($probabilities); $index++) {
        if ($probabilities[$index] > $probabilities[$predicted]) {
            $predicted = $index;
        }
    }
    $loss = log($total) - $shifted[$label];
    return (object) compact('probabilities', 'predicted', 'loss');
}

function softmaxEvaluate(array $weights, array $vectors, array $labels, float $lambda = 0.0): object
{
    $rows = [];
    $total = 0.0;
    foreach ($vectors as $index => $vector) {
        $row = softmaxRow($weights, $vector, $labels[$index]);
        $rows[] = $row;
        $total += $row->loss;
    }
    $squared = 0.0;
    foreach ($weights as $classWeights) {
        for ($component = 1; $component < count($classWeights); $component++) {
            $squared += $classWeights[$component] * $classWeights[$component];
        }
    }
    $loss = $total / count($vectors);
    $objective = $loss + $lambda * $squared / 2.0;
    return (object) compact('rows', 'loss', 'objective');
}

function softmaxGradient(array $weights, array $vectors, array $labels, float $lambda): array
{
    $probabilities = array_map(fn($vector) => softmaxRow($weights, $vector)->probabilities, $vectors);
    $gradient = [];
    foreach ($weights as $label => $classWeights) {
        $direction = [];
        foreach ($classWeights as $component => $weight) {
            $total = 0.0;
            foreach ($vectors as $row => $vector) {
                $error = $probabilities[$row][$label] - (int) ($labels[$row] === $label);
                $total += $error * $vector[$component];
            }
            $value = $total / count($vectors);
            $direction[] = $component === 0 ? $value : $value + $lambda * $weight;
        }
        $gradient[] = $direction;
    }
    return $gradient;
}

function trainSoftmax(array $vectors, array $labels, int $classes, float $lambda, float $rate, int $iterations): object
{
    $weights = array_fill(0, $classes, array_fill(0, count($vectors[0]), 0.0));
    $checkpoints = [(object) ['iteration' => 0, 'weights' => $weights]];
    for ($iteration = 1; $iteration <= $iterations; $iteration++) {
        $direction = softmaxGradient($weights, $vectors, $labels, $lambda);
        foreach ($weights as $label => $row) {
            foreach ($row as $component => $weight) {
                $weights[$label][$component] = $weight - $rate * $direction[$label][$component];
            }
        }
        if ($iteration % 100 === 0) {
            $checkpoints[] = (object) compact('iteration', 'weights');
        }
    }
    return (object) compact('weights', 'checkpoints');
}
