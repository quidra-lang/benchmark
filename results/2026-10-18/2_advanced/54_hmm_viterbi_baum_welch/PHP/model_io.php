<?php

function normalize_values($values)
{
    $total = 0.0;
    foreach ($values as $value) $total += $value;
    $result = [];
    foreach ($values as $value) $result[] = $value / $total;
    return $result;
}

function model_with_probabilities($model, $name, $initial, $transition, $emission)
{
    $model['name'] = $name;
    $model['initial'] = $initial;
    $model['transition'] = $transition;
    $model['emission'] = $emission;
    return $model;
}

function read_rows($filename)
{
    $rows = [];
    foreach (file('input/' . $filename, FILE_IGNORE_NEW_LINES) as $line) $rows[] = explode(' ', $line);
    return $rows;
}

function read_inputs()
{
    $rows = read_rows('model.txt');
    $states = array_slice($rows[0], 1);
    $symbols = array_slice($rows[1], 1);
    $count = count($states);
    $initial = normalize_values(array_map('floatval', array_slice($rows[3], 1)));
    $transition = [];
    $emission = [];
    for ($i = 0; $i < $count; $i++) {
        $transition[] = normalize_values(array_map('floatval', array_slice($rows[4 + $i], 2)));
        $emission[] = normalize_values(array_map('floatval', array_slice($rows[4 + $count + $i], 2)));
    }
    $model = ['name' => 'INITIAL', 'states' => $states, 'symbols' => $symbols, 'missing' => $rows[2][1],
        'initial' => $initial, 'transition' => $transition, 'emission' => $emission];
    return ['model' => $model, 'sequences' => read_rows('sequences.txt'), 'labeled' => read_rows('labeled.txt'), 'parameters' => read_rows('params.txt')];
}

function real_number($value, $digits = 4)
{
    if ($value === null) return '-';
    $text = sprintf('%.' . $digits . 'F', $value);
    return $text === ('-0.' . str_repeat('0', $digits)) ? substr($text, 1) : $text;
}

function model_lines($model)
{
    $lines = ['MODEL ' . $model['name'], 'STATES ' . implode(' ', $model['states']), 'SYMBOLS ' . implode(' ', $model['symbols']),
        'MISSING ' . $model['missing'], 'INITIAL ' . implode(' ', array_map('real_number', $model['initial']))];
    foreach ($model['states'] as $i => $state) $lines[] = 'TRANSITION ' . $state . ' ' . implode(' ', array_map('real_number', $model['transition'][$i]));
    foreach ($model['states'] as $i => $state) $lines[] = 'EMISSION ' . $state . ' ' . implode(' ', array_map('real_number', $model['emission'][$i]));
    return $lines;
}

function write_lines($filename, $lines)
{
    if (!is_dir('output')) mkdir('output', 0777, true);
    file_put_contents('output/' . $filename, implode("\n", $lines) . "\n");
}
