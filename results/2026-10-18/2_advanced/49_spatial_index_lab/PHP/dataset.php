<?php

function inputLines($name) {
    return file('input/' . $name, FILE_IGNORE_NEW_LINES);
}

function makePoint($id, $x, $y) {
    return ['id' => $id, 'x' => $x, 'y' => $y, 'box' => [$x, $y, $x, $y]];
}

function readDataset() {
    $points = [];
    foreach (array_slice(inputLines('points.csv'), 1) as $line) {
        [$id, $x, $y] = array_map('intval', explode(',', $line));
        $points[] = makePoint($id, $x, $y);
    }
    $rectangles = [];
    foreach (array_slice(inputLines('rects.csv'), 1) as $line) {
        $values = array_map('intval', explode(',', $line));
        $id = array_shift($values);
        $rectangles[] = ['id' => $id, 'box' => $values];
    }
    $parameters = [];
    foreach (inputLines('params.txt') as $line) {
        $values = explode(' ', $line);
        array_shift($values);
        $parameters[] = array_map('intval', $values);
    }
    $settings = ['world' => $parameters[0][0], 'bucket' => $parameters[1][0], 'maximum' => $parameters[2][0], 'minimum' => $parameters[2][1], 'cell' => $parameters[3][0]];
    $commands = [];
    foreach (inputLines('queries.txt') as $line) {
        $values = explode(' ', $line);
        $name = array_shift($values);
        $commands[] = ['name' => $name, 'args' => array_map('intval', $values)];
    }
    return compact('points', 'rectangles', 'settings', 'commands');
}
