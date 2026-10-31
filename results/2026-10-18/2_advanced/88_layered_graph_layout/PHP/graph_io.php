<?php

const DEFAULTS = [
    'layering' => 'longest',
    'width' => 4,
    'promotion' => 'off',
    'heuristic' => 'barycenter',
    'sweeps' => 12,
    'node_sep' => 2,
    'dummy_sep' => 1,
    'layer_gap' => 3,
    'direction' => 'TB',
    'sifting' => 'off',
    'reduce' => 'off',
    'restarts' => 0,
    'seed' => 1,
];

const CHOICES = [
    'layering' => ['longest', 'coffman'],
    'promotion' => ['on', 'off'],
    'heuristic' => ['barycenter', 'median'],
    'direction' => ['TB', 'BT', 'LR', 'RL'],
    'sifting' => ['on', 'off'],
    'reduce' => ['on', 'off'],
];

const RANGES = [
    'width' => [1, 40],
    'sweeps' => [0, 50],
    'node_sep' => [1, 9],
    'dummy_sep' => [1, 9],
    'layer_gap' => [2, 9],
    'restarts' => [0, 9],
    'seed' => [1, 2147483646],
];

function settingValue(string $name, string $word): string|int|null
{
    if (isset(CHOICES[$name]))
        return in_array($word, CHOICES[$name], true) ? $word : null;
    if (isset(RANGES[$name]) && preg_match('/\A[0-9]{1,10}\z/', $word)) {
        $value = (int) $word;
        [$lo, $hi] = RANGES[$name];
        if ($value >= $lo && $value <= $hi)
            return $value;
    }
    return null;
}

function inputLines(string $file): array
{
    $lines = [];
    foreach (file('input/' . $file, FILE_IGNORE_NEW_LINES) as $i => $line)
        if ($line !== '' && $line[0] !== '#')
            $lines[] = [$i + 1, explode(' ', $line)];
    return $lines;
}

function readGraphs(): array
{
    $defaults = DEFAULTS;
    foreach (inputLines('params.txt') as [$line, [$name, $word]])
        $defaults[$name] = settingValue($name, $word);
    $graphs = [];
    $g = null;
    foreach (inputLines('graphs.txt') as [$number, $f]) {
        $kind = $f[0];
        if ($kind === 'GRAPH') {
            $g = (object) [
                'name' => $f[1],
                'settings' => $defaults,
                'nodes' => [],
                'edges' => [],
                'edgeSet' => [],
                'path' => null,
                'selfLoops' => 0,
                'duplicates' => 0,
                'error' => null,
            ];
            $graphs[] = $g;
            continue;
        }
        if ($kind === 'END') {
            if ($g->error === null && !$g->nodes)
                $g->error = ['no_nodes', $number];
            continue;
        }
        if ($g->error !== null)
            continue;
        $error = null;
        if ($kind === 'OPTION') {
            $value = settingValue($f[1], $f[2]);
            if ($value === null)
                $error = 'bad_option';
            else
                $g->settings[$f[1]] = $value;
        } elseif ($kind === 'NODE') {
            $id = (int) $f[1];
            if (isset($g->nodes[$id]))
                $error = 'duplicate_node';
            elseif (count($g->nodes) === 40)
                $error = 'too_many_nodes';
            else
                $g->nodes[$id] = $f[2];
        } else {
            $a = (int) $f[1];
            $b = (int) $f[2];
            if (!isset($g->nodes[$a], $g->nodes[$b]))
                $error = 'unknown_node';
            elseif ($kind === 'PATH')
                $g->path = [$a, $b];
            elseif ($a === $b)
                ++$g->selfLoops;
            elseif (isset($g->edgeSet[$a . ':' . $b]))
                ++$g->duplicates;
            else {
                $g->edgeSet[$a . ':' . $b] = true;
                $g->edges[] = [$a, $b];
            }
        }
        if ($error !== null)
            $g->error = [$error, $number];
    }
    return $graphs;
}
