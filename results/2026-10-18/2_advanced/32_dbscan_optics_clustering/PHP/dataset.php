<?php

function readDataset(): object
{
    $points = [];
    foreach (array_slice(file('input/points.csv', FILE_IGNORE_NEW_LINES), 1) as $line) {
        [$id, $x, $y] = array_map('intval', explode(',', $line));
        $points[] = (object) compact('id', 'x', 'y');
    }
    usort($points, fn($a, $b) => $a->id <=> $b->id);
    $fields = [];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $parts = explode(' ', $line);
        $name = array_shift($parts);
        $fields[$name] = $parts;
    }
    $parameters = (object) ['eps' => array_map('intval', $fields['EPS']), 'minimum' => (int) $fields['MIN_PTS'][0],
        'maximum' => (int) $fields['OPTICS_MAX_EPS'][0], 'extracts' => array_map('intval', $fields['EXTRACT_EPS']),
        'xi' => array_map('intval', explode('/', $fields['XI'][0])), 'xiText' => $fields['XI'][0],
        'minimumSize' => (int) $fields['XI_MIN_SIZE'][0], 'mapSize' => array_map('intval', $fields['MAP_SIZE']),
        'kdistSize' => array_map('intval', $fields['KDIST_PLOT']), 'reachWidth' => (int) $fields['PLOT_WIDTH'][0]];
    return (object) compact('points', 'parameters');
}
