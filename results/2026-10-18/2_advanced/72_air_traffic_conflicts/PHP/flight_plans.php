<?php

function read_lines($path) { return file($path, FILE_IGNORE_NEW_LINES); }

function load_all()
{
    $types = [];
    foreach (read_lines('input/aircraft.txt') as $line) {
        [$name, $climb, $descent, $minimum] = explode(' ', $line);
        $types[$name] = ['climb' => (int) $climb, 'descent' => (int) $descent, 'minimum' => (int) $minimum];
    }
    $sectors = [];
    foreach (read_lines('input/sectors.txt') as $index => $line) {
        [$name, $x1, $y1, $x2, $y2, $lower, $upper, $capacity] = explode(' ', $line);
        $sectors[] = ['name' => $name, 'index' => $index, 'x1' => (int) $x1, 'y1' => (int) $y1, 'x2' => (int) $x2, 'y2' => (int) $y2,
            'lower' => (int) $lower, 'upper' => (int) $upper, 'capacity' => (int) $capacity];
    }
    $rows = [];
    foreach (read_lines('input/params.txt') as $line) $rows[] = array_map('intval', array_slice(explode(' ', $line), 1));
    $params = ['dh' => $rows[0][0], 'dv' => $rows[0][1], 'lookahead' => $rows[1][0], 'maxDelay' => $rows[2][0],
        'levelMin' => $rows[3][0], 'levelMax' => $rows[3][1], 'sampleStart' => $rows[4][0], 'sampleEnd' => $rows[4][1],
        'radar' => $rows[5], 'snapshots' => $rows[6], 'leader' => $rows[7][0], 'alert' => $rows[8][0]];
    $flights = [];
    foreach (array_slice(read_lines('input/flights.csv'), 1) as $line) {
        [$callsign, $type, $departure, $level, $speed, $words] = explode(',', $line);
        $waypoints = [];
        foreach (explode(' ', $words) as $word) {
            $coords = array_map('intval', explode(':', $word));
            $waypoints[] = ['x' => $coords[0], 'y' => $coords[1], 'level' => $coords[2] ?? null];
        }
        $flights[$callsign] = ['callsign' => $callsign, 'type' => $type, 'departure' => (int) $departure, 'level' => (int) $level,
            'speedInitial' => (int) $speed, 'speed' => (int) $speed, 'delay' => 0, 'offset' => 0, 'history' => [], 'waypoints' => $waypoints];
    }
    return compact('flights', 'types', 'sectors', 'params');
}

function level_list($plan)
{
    $levels = [$plan['level'] + $plan['offset']];
    foreach (array_slice($plan['waypoints'], 1) as $w) if ($w['level'] !== null) $levels[] = $w['level'] + $plan['offset'];
    return $levels;
}
