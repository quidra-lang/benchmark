<?php

function triangulate(array $polygons): array
{
    $triangles = [];
    foreach ($polygons as $polygon) {
        for ($i = 1; $i < count($polygon['vertices']) - 1; $i++) {
            $triangles[] = ['number' => count($triangles) + 1, 'vertices' => [$polygon['vertices'][0],
                $polygon['vertices'][$i], $polygon['vertices'][$i + 1]], 'polygon' => $polygon];
        }
    }
    return $triangles;
}

function snapVertices(array $vertices, int $spacing): array
{
    $positions = [null];
    $changed = [];
    for ($i = 1; $i < count($vertices); $i++) {
        $position = [];
        foreach ($vertices[$i] as $value) {
            $numerator = 2 * $value + $spacing;
            $denominator = 2 * $spacing;
            $quotient = intdiv($numerator, $denominator);
            if ($numerator < 0 && $numerator % $denominator !== 0) $quotient--;
            $position[] = $spacing * $quotient;
        }
        $positions[] = $position;
        if ($position !== $vertices[$i]) $changed[] = ['original' => $i, 'before' => $vertices[$i], 'after' => $position];
    }
    return compact('positions', 'changed');
}

function representatives(array $positions, bool $merge): array
{
    $numbers = [null];
    $first = [];
    $groups = [];
    $merged = 0;
    for ($i = 1; $i < count($positions); $i++) {
        $key = implode(',', $positions[$i]);
        if (!isset($first[$key])) $first[$key] = $i;
        $representative = $merge ? $first[$key] : $i;
        $numbers[] = $representative;
        $groups[$representative][] = $i;
        if ($representative !== $i) $merged++;
    }
    return compact('numbers', 'groups', 'merged');
}

function removeTriangles(array $triangles, array $representatives, array $positions, array $settings): array
{
    $faces = [];
    $removed = [];
    $seen = [];
    foreach ($triangles as $triangle) {
        $vertices = array_map(fn($v) => $representatives[$v], $triangle['vertices']);
        $sorted = $vertices;
        sort($sorted, SORT_NUMERIC);
        $key = implode(',', $sorted);
        $reason = null;
        if (count(array_unique($vertices)) < 3) $reason = 'repeated';
        elseif ($settings['degenerate'] && normal(['vertices' => $vertices], $positions) === [0, 0, 0]) $reason = 'zero_area';
        elseif ($settings['duplicates'] && isset($seen[$key])) $reason = 'duplicate';
        if ($reason !== null) {
            $removed[] = compact('triangle', 'reason');
        } else {
            $seen[$key] = true;
            $faces[] = ['vertices' => $vertices, 'group' => $triangle['polygon']['group'],
                'polygon' => $triangle['polygon'], 'triangle' => $triangle['number']];
        }
    }
    return compact('faces', 'removed');
}

function fillTriangles(array $loop): array
{
    $faces = [];
    for ($i = 1; $i < count($loop['vertices']) - 1; $i++) {
        $faces[] = ['vertices' => [$loop['vertices'][0], $loop['vertices'][$i + 1], $loop['vertices'][$i]],
            'group' => 'fill', 'polygon' => null];
    }
    return $faces;
}
