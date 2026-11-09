<?php

function read_input_lines($name)
{
    return file('input/' . $name, FILE_IGNORE_NEW_LINES);
}

function binary_rows($lines)
{
    $rows = [];
    foreach (array_slice($lines, 1) as $line) {
        $fields = explode(',', $line);
        $rows[] = ['id' => $fields[0], 'values' => array_map('floatval', array_slice($fields, 1, -1)),
            'label' => (int) $fields[count($fields) - 1]];
    }
    return $rows;
}

function read_dataset()
{
    $trainLines = read_input_lines('train.csv');
    $testLines = read_input_lines('test.csv');
    $multiLines = read_input_lines('multiclass.csv');
    $features = array_slice(explode(',', $trainLines[0]), 1, -1);
    $multiFeatures = array_slice(explode(',', $multiLines[0]), 1, -2);
    $multiTrain = [];
    $multiTest = [];
    foreach (array_slice($multiLines, 1) as $line) {
        $fields = explode(',', $line);
        $count = count($fields);
        $row = ['id' => $fields[0], 'values' => array_map('floatval', array_slice($fields, 1, -2)), 'category' => (int) $fields[$count - 2]];
        if ($fields[$count - 1] === 'train') $multiTrain[] = $row;
        else $multiTest[] = $row;
    }
    $settings = [];
    foreach (read_input_lines('params.txt') as $line) $settings[] = array_slice(explode(' ', $line), 1);
    $params = ['rounds' => (int) $settings[0][0], 'variants' => $settings[1], 'bins' => (int) $settings[2][0],
        'smoothing' => (float) $settings[3][0], 'convergence' => (float) $settings[4][0],
        'clip' => (float) $settings[5][0], 'folds' => (int) $settings[6][0], 'margins' => array_map('floatval', $settings[7]),
        'classes' => (int) $settings[8][0], 'sammeRounds' => (int) $settings[9][0],
        'permutationRepeats' => (int) $settings[10][0], 'permutationSeed' => (int) $settings[10][1],
        'noiseSeed' => (int) $settings[11][0], 'noise' => array_map('intval', array_slice($settings[11], 1)),
        'sizes' => array_map('intval', $settings[12]), 'shrinkage' => array_map('floatval', $settings[13]),
        'bootstrapSamples' => (int) $settings[14][0], 'bootstrapSeed' => (int) $settings[14][1]];
    return ['features' => $features, 'train' => binary_rows($trainLines), 'test' => binary_rows($testLines),
        'multiFeatures' => $multiFeatures, 'multiTrain' => $multiTrain, 'multiTest' => $multiTest, 'params' => $params];
}
