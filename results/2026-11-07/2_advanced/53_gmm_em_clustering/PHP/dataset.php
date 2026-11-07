<?php

function inputLines($name) {
    return file('input/' . $name, FILE_IGNORE_NEW_LINES);
}

function readDataset() {
    $points = [];
    foreach (array_slice(inputLines('points.csv'), 1) as $line) {
        [$id, $x, $y] = explode(',', $line);
        $points[] = ['id' => $id, 'x' => (float)$x, 'y' => (float)$y];
    }
    $settings = [];
    foreach (inputLines('params.txt') as $line) {
        $values = explode(' ', $line);
        $name = array_shift($values);
        $settings[$name] = $values;
    }
    $params = [
        'ks' => array_map('intval', $settings['K']), 'types' => $settings['TYPES'],
        'iterations' => (int)$settings['ITERATIONS'][0], 'eps' => (float)$settings['REGULARIZATION'][0],
        'tau' => (float)$settings['SETTLE_TOLERANCE'][0], 'kmeansMax' => (int)$settings['KMEANS_MAX_ITERATIONS'][0],
        'folds' => (int)$settings['CV_FOLDS'][0], 'uncertain' => (float)$settings['UNCERTAIN_THRESHOLD'][0],
        'lowDensity' => (float)$settings['LOW_DENSITY_THRESHOLD'][0], 'edges' => array_map('floatval', $settings['GOF_EDGES']),
        'xmin' => (float)$settings['MAP_X'][0], 'xmax' => (float)$settings['MAP_X'][1],
        'ymin' => (float)$settings['MAP_Y'][0], 'ymax' => (float)$settings['MAP_Y'][1],
        'width' => (int)$settings['MAP_SIZE'][0], 'height' => (int)$settings['MAP_SIZE'][1]
    ];
    $initial = [];
    foreach (inputLines('init.txt') as $line) {
        if ($line === '') continue;
        $parts = explode(' ', $line);
        if ($parts[0] === 'K') {
            $k = (int)$parts[1];
            $initial[$k] = [];
        } elseif ($parts[0] === 'W') {
            $weights = array_map('floatval', array_slice($parts, 1));
        } else {
            $j = (int)$parts[1] - 1;
            $initial[$k][] = ['w' => $weights[$j], 'mx' => (float)$parts[2], 'my' => (float)$parts[3],
                'a' => (float)$parts[4], 'b' => (float)$parts[5], 'c' => (float)$parts[6]];
        }
    }
    return compact('points', 'params', 'initial');
}
