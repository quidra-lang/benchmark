<?php

function score(array $weights, array $vector): float
{
    $total = 0.0;
    foreach ($weights as $component => $weight) {
        $total += $weight * $vector[$component];
    }
    return $total;
}

function sigmoid(float $value): float
{
    if ($value >= 0) {
        return 1.0 / (1.0 + exp(-$value));
    }
    $exponential = exp($value);
    return $exponential / (1.0 + $exponential);
}

function logisticLoss(float $value, int $target): float
{
    return max($value, 0.0) - $target * $value + log(1.0 + exp(-abs($value)));
}

function logisticEvaluate(array $weights, array $vectors, array $targets, float $lambda = 0.0): object
{
    $scores = $probabilities = [];
    $total = 0.0;
    foreach ($vectors as $row => $vector) {
        $value = score($weights, $vector);
        $scores[] = $value;
        $probabilities[] = sigmoid($value);
        $total += logisticLoss($value, $targets[$row]);
    }
    $squared = 0.0;
    for ($component = 1; $component < count($weights); $component++) {
        $squared += $weights[$component] * $weights[$component];
    }
    $loss = $total / count($vectors);
    $objective = $loss + $lambda * $squared / 2.0;
    return (object) compact('scores', 'probabilities', 'loss', 'objective');
}

function logisticGradient(array $weights, array $vectors, array $targets, float $lambda): array
{
    $errors = [];
    foreach ($vectors as $row => $vector) {
        $errors[] = sigmoid(score($weights, $vector)) - $targets[$row];
    }
    $gradient = [];
    foreach ($weights as $component => $weight) {
        $total = 0.0;
        foreach ($vectors as $row => $vector) {
            $total += $errors[$row] * $vector[$component];
        }
        $value = $total / count($vectors);
        $gradient[] = $component === 0 ? $value : $value + $lambda * $weight;
    }
    return $gradient;
}

function logisticHessian(array $weights, array $vectors, float $lambda): array
{
    $variances = [];
    foreach ($vectors as $vector) {
        $probability = sigmoid(score($weights, $vector));
        $variances[] = $probability * (1.0 - $probability);
    }
    $matrix = array_fill(0, count($weights), array_fill(0, count($weights), 0.0));
    for ($first = 0; $first < count($weights); $first++) {
        for ($second = 0; $second <= $first; $second++) {
            $total = 0.0;
            foreach ($vectors as $row => $vector) {
                $total += $variances[$row] * $vector[$first] * $vector[$second];
            }
            $value = $total / count($vectors);
            if ($first === $second && $first >= 1) {
                $value += $lambda;
            }
            $matrix[$first][$second] = $matrix[$second][$first] = $value;
        }
    }
    return $matrix;
}
