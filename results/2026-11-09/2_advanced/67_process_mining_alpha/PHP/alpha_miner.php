<?php

require_once __DIR__ . '/dfg.php';

function compare_sequences($first, $second)
{
    for ($i = 0; $i < min(count($first), count($second)); $i++) {
        $result = strcmp($first[$i], $second[$i]);
        if ($result !== 0) return $result;
    }
    return count($first) <=> count($second);
}

function compare_pairs($first, $second)
{
    return compare_sequences($first['A'], $second['A']) ?: compare_sequences($first['B'], $second['B']);
}

function extend_pair($pair, $activity, $side, $relation)
{
    $own = $pair[$side];
    if (in_array($activity, $own, true) || $relation($activity, $activity) !== '#') return null;
    foreach ($own as $other) if ($relation($activity, $other) !== '#') return null;
    if ($side === 'A') foreach ($pair['B'] as $other) { if ($relation($activity, $other) !== '->') return null; }
    if ($side === 'B') foreach ($pair['A'] as $other) { if ($relation($other, $activity) !== '->') return null; }
    $result = ['A' => $pair['A'], 'B' => $pair['B']];
    $result[$side][] = $activity;
    sort($result[$side], SORT_STRING);
    return $result;
}

function triangle_counts($log)
{
    $triangles = [];
    foreach ($log as $entry) for ($i = 0; $i + 2 < count($entry['trace']); $i++) {
        $trace = $entry['trace'];
        if ($trace[$i] !== $trace[$i + 1] && $trace[$i] === $trace[$i + 2]) {
            $key = pair_key($trace[$i], $trace[$i + 1]);
            $triangles[$key] = ($triangles[$key] ?? 0) + $entry['weight'];
        }
    }
    return $triangles;
}

function alpha_plus_relation($counts, $triangles)
{
    $causal = fn($a, $b) => follows_count($counts, $a, $b) > 0 && (follows_count($counts, $b, $a) === 0 ||
        ($a !== $b && follows_count($triangles, $a, $b) > 0 && follows_count($triangles, $b, $a) > 0));
    return function ($a, $b) use ($counts, $causal) {
        if ($causal($a, $b)) return '->';
        if ($causal($b, $a)) return '<-';
        return follows_count($counts, $a, $b) > 0 && follows_count($counts, $b, $a) > 0 ? '||' : '#';
    };
}
