<?php

function pair_key($first, $second) { return $first . "\0" . $second; }
function follows_count($counts, $first, $second) { return $counts[pair_key($first, $second)] ?? 0; }

function count_follows($log)
{
    $counts = [];
    foreach ($log as $entry) for ($i = 1; $i < count($entry['trace']); $i++) {
        $key = pair_key($entry['trace'][$i - 1], $entry['trace'][$i]);
        $counts[$key] = ($counts[$key] ?? 0) + $entry['weight'];
    }
    return $counts;
}

function basic_relation($counts, $first, $second)
{
    $forward = follows_count($counts, $first, $second) > 0;
    $reverse = follows_count($counts, $second, $first) > 0;
    return $forward ? ($reverse ? '||' : '->') : ($reverse ? '<-' : '#');
}

function format_table($rows, $width)
{
    $header = '    ';
    foreach ($rows as $i => $row) $header .= str_pad((string) ($i + 1), $width, ' ', STR_PAD_LEFT);
    $lines = [$header];
    foreach ($rows as $i => $row) {
        $line = str_pad((string) ($i + 1), 4, ' ', STR_PAD_LEFT);
        foreach ($row as $value) $line .= str_pad((string) $value, $width, ' ', STR_PAD_LEFT);
        $lines[] = $line;
    }
    return $lines;
}

function footprint($activities, $relation)
{
    $lines = []; $cells = [];
    foreach ($activities as $i => $activity) $lines[] = 'ACTIVITY ' . ($i + 1) . ' ' . $activity;
    foreach ($activities as $first) {
        $row = [];
        foreach ($activities as $second) $row[] = $relation($first, $second);
        $cells[] = $row;
    }
    return array_merge($lines, format_table($cells, 4));
}
