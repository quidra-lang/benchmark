<?php

function inputLines($name) {
    return file('input/' . $name, FILE_IGNORE_NEW_LINES);
}

function readTable($name, $known = null) {
    $lines = inputLines($name);
    $header = explode(',', array_shift($lines));
    $raw = array_map(fn($line) => explode(',', $line), $lines);
    $columns = [];
    foreach ($header as $i => $column) {
        $categorical = false;
        if ($known !== null) {
            foreach ($known as $entry) {
                if ($entry['name'] === $column) {
                    $categorical = $entry['categorical'];
                    break;
                }
            }
        } else {
            foreach ($raw as $row) {
                if ($row[$i] !== 'NA' && $row[$i][0] >= 'A' && $row[$i][0] <= 'Z') {
                    $categorical = true;
                    break;
                }
            }
        }
        $columns[] = ['name' => $column, 'categorical' => $categorical];
    }
    $rows = [];
    foreach ($raw as $i => $row) {
        $values = [];
        foreach ($columns as $j => $column) {
            $value = $row[$j];
            $values[$column['name']] = $value === 'NA' ? null : ($column['categorical'] ? $value : (float)$value);
        }
        $rows[] = ['number' => $i + 1, 'values' => $values];
    }
    return ['columns' => $columns, 'rows' => $rows];
}

function readInput() {
    $data = readTable('data.csv');
    $predictions = readTable('predict.csv', $data['columns']);
    $parameters = [];
    foreach (inputLines('params.txt') as $line) {
        $parts = explode(' ', $line);
        $name = array_shift($parts);
        $parameters[$name] = $name === 'PLOT' ? [(int)$parts[0], (int)$parts[1], (float)$parts[2]] : (float)$parts[0];
    }
    return ['data' => $data, 'predictions' => $predictions, 'models' => inputLines('model.txt'), 'parameters' => $parameters];
}
