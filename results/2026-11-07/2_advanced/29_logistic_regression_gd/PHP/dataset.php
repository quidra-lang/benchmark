<?php

function readTable(string $path): object
{
    $lines = file($path, FILE_IGNORE_NEW_LINES);
    $header = explode(',', array_shift($lines));
    $names = array_slice($header, 1, -1);
    $ids = $base = $labels = [];
    foreach ($lines as $line) {
        $fields = explode(',', $line);
        $ids[] = $fields[0];
        $base[] = array_map('floatval', array_slice($fields, 1, -1));
        $labels[] = (int) $fields[count($fields) - 1];
    }
    return (object) compact('names', 'ids', 'base', 'labels');
}

function readInputs(): object
{
    $train = readTable('input/train.csv');
    $test = readTable('input/test.csv');
    $parameters = [];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $fields = explode(' ', $line);
        $name = array_shift($fields);
        $parameters[$name] = $fields;
    }
    $settings = (object) [
        'positive' => (int) $parameters['POSITIVE'][0], 'degree' => (int) $parameters['DEGREE'][0],
        'threshold' => (float) $parameters['THRESHOLD'][0], 'lambdas' => array_map('floatval', $parameters['LAMBDAS']),
        'gd' => [(float) $parameters['GD'][0], (int) $parameters['GD'][1]],
        'sgd' => [(float) $parameters['SGD'][0], (int) $parameters['SGD'][1], (int) $parameters['SGD'][2], (int) $parameters['SGD'][3]],
        'softmax' => [(float) $parameters['SOFTMAX'][0], (int) $parameters['SOFTMAX'][1], (float) $parameters['SOFTMAX'][2]],
        'bootstrap' => array_map('intval', $parameters['BOOTSTRAP']), 'permutation' => array_map('intval', $parameters['PERMUTATION']),
        'map' => array_map('intval', $parameters['MAP']), 'cost' => array_map('intval', $parameters['COST'])
    ];
    return (object) ['names' => $train->names, 'train' => $train, 'test' => $test, 'settings' => $settings];
}

function expandedFeatures(array $names, int $maximumDegree): array
{
    $features = [];
    $visit = function (array $tuple, int $start, int $remaining) use (&$visit, &$features, $names): void {
        if ($remaining === 0) {
            $features[] = (object) ['tuple' => $tuple, 'degree' => count($tuple),
                'name' => implode('*', array_map(fn($index) => $names[$index], $tuple))];
            return;
        }
        for ($index = $start; $index < count($names); $index++) {
            $next = $tuple;
            $next[] = $index;
            $visit($next, $index, $remaining - 1);
        }
    };
    for ($degree = 1; $degree <= $maximumDegree; $degree++) {
        $visit([], 0, $degree);
    }
    return $features;
}

function expand(array $base, array $features): array
{
    $values = [];
    foreach ($features as $feature) {
        $value = $base[$feature->tuple[0]];
        for ($i = 1; $i < count($feature->tuple); $i++) {
            $value *= $base[$feature->tuple[$i]];
        }
        $values[] = $value;
    }
    return $values;
}

function featureStatistics(array $values, ?int $width = null): object
{
    $width ??= count($values[0]);
    $means = $deviations = [];
    for ($feature = 0; $feature < $width; $feature++) {
        $total = 0.0;
        foreach ($values as $row) {
            $total += $row[$feature];
        }
        $mean = $total / count($values);
        $squared = 0.0;
        foreach ($values as $row) {
            $squared += ($row[$feature] - $mean) * ($row[$feature] - $mean);
        }
        $means[] = $mean;
        $deviations[] = sqrt($squared / (count($values) - 1));
    }
    return (object) compact('means', 'deviations');
}

function standardizeOne(array $values, object $stats): array
{
    $vector = [1.0];
    foreach ($stats->means as $index => $mean) {
        $vector[] = ($values[$index] - $mean) / $stats->deviations[$index];
    }
    return $vector;
}

function standardize(array $values, object $stats): array
{
    return array_map(fn($row) => standardizeOne($row, $stats), $values);
}
