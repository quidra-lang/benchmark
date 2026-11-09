<?php

function samplesPerTick(int $rate, int $tempo): int
{
    return intdiv($rate * 5, $tempo * 2);
}

function nextRow(object $song, int $position, int $row): object
{
    $cells = $song->patterns[$song->order[$position]][$row];
    $jump = $breakRow = null;
    $stop = false;
    foreach ($cells as $cell) {
        $effect = $cell->effect;
        if (($effect->name ?? null) === 'F' && $effect->argument === 0) {
            $stop = true;
        }
        if (($effect->name ?? null) === 'B') {
            $jump = $effect->argument;
        }
        if (($effect->name ?? null) === 'D') {
            $breakRow = $effect->argument >= 64 ? 0 : $effect->argument;
        }
    }
    if ($stop) {
        return (object) ['reason' => 'stop', 'position' => $position, 'row' => $row];
    }
    if ($jump !== null || $breakRow !== null) {
        $nextPosition = $jump ?? $position + 1;
        $next = $breakRow ?? 0;
    } else {
        $nextPosition = $row === 63 ? $position + 1 : $position;
        $next = $row === 63 ? 0 : $row + 1;
    }
    return $nextPosition >= count($song->order) ? (object) ['reason' => 'finished'] : (object) ['position' => $nextPosition, 'row' => $next];
}

function reachableRows(object $song): array
{
    $reachable = [];
    $current = (object) ['position' => 0, 'row' => 0];
    while (!isset($current->reason)) {
        $key = $current->position . ',' . $current->row;
        if (isset($reachable[$key])) {
            break;
        }
        $reachable[$key] = true;
        $current = nextRow($song, $current->position, $current->row);
    }
    return $reachable;
}
