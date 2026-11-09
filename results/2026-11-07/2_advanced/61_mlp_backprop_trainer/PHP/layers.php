<?php

function activate(string $kind, float $value): float
{
    if ($kind === 'TANH') {
        return tanh($value);
    }
    if ($kind === 'SIGMOID') {
        return 1 / (1 + exp(-$value));
    }
    return $value > 0 ? $value : 0.0;
}

function derivative(string $kind, float $value, float $activation): float
{
    if ($kind === 'TANH') {
        return 1 - $activation * $activation;
    }
    if ($kind === 'SIGMOID') {
        return $activation * (1 - $activation);
    }
    return $value > 0 ? 1.0 : 0.0;
}

function preactivate(array $theta, object $layer, array $inputs): array
{
    $values = [];
    for ($j = 0; $j < $layer->units; $j++) {
        $weighted = 0.0;
        $offset = $layer->offset + $j * $layer->inputs;
        for ($i = 0; $i < $layer->inputs; $i++) {
            $weighted += $theta[$offset + $i] * $inputs[$i];
        }
        $values[] = $weighted + $theta[$layer->biasOffset + $j];
    }
    return $values;
}

function propagate(array $theta, object $layer, array $errors): array
{
    $values = [];
    for ($i = 0; $i < $layer->inputs; $i++) {
        $value = 0.0;
        for ($j = 0; $j < $layer->units; $j++) {
            $value += $theta[$layer->offset + $j * $layer->inputs + $i] * $errors[$j];
        }
        $values[] = $value;
    }
    return $values;
}

function outputLayer(string $kind, array $values, int $label): object
{
    $size = count($values);
    $errors = [];
    $scores = [];
    if ($kind === 'SOFTMAX') {
        $maximum = max($values);
        $exponentials = [];
        $total = 0.0;
        foreach ($values as $value) {
            $exponential = exp($value - $maximum);
            $exponentials[] = $exponential;
            $total += $exponential;
        }
        foreach ($exponentials as $value) {
            $scores[] = $value / $total;
        }
        $loss = log($total) - ($values[$label] - $maximum);
        for ($k = 0; $k < $size; $k++) {
            $errors[] = $scores[$k] - ($k === $label ? 1 : 0);
        }
    } else {
        $loss = 0.0;
        foreach ($values as $value) {
            $scores[] = activate('SIGMOID', $value);
        }
        for ($k = 0; $k < $size; $k++) {
            $difference = $scores[$k] - ($k === $label ? 1 : 0);
            $loss += $difference * $difference;
            $errors[] = 2 * $difference * $scores[$k] * (1 - $scores[$k]) / $size;
        }
        $loss /= $size;
    }
    return (object) ['scores' => $scores, 'loss' => $loss, 'errors' => $errors];
}
