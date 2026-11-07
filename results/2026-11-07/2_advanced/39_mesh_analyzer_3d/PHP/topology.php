<?php

function edgeKey(int $a, int $b): string
{
    return min($a, $b) . ',' . max($a, $b);
}

function findRoot(array &$parents, int $value): int
{
    $root = $value;
    while ($parents[$root] !== $root) $root = $parents[$root];
    while ($parents[$value] !== $value) {
        $next = $parents[$value];
        $parents[$value] = $root;
        $value = $next;
    }
    return $root;
}

function joinRoots(array &$parents, int $a, int $b): void
{
    $ra = findRoot($parents, $a);
    $rb = findRoot($parents, $b);
    $parents[$rb] = $ra;
}

function analyze(array $faces): array
{
    $edgeMap = [];
    $vertexFaces = [];
    foreach ($faces as $index => $face) {
        $vertices = $face['vertices'];
        foreach ($vertices as $vertex) $vertexFaces[$vertex][] = $index;
        for ($i = 0; $i < 3; $i++) {
            $a = min($vertices[$i], $vertices[($i + 1) % 3]);
            $b = max($vertices[$i], $vertices[($i + 1) % 3]);
            $key = edgeKey($a, $b);
            if (!isset($edgeMap[$key])) $edgeMap[$key] = ['a' => $a, 'b' => $b, 'key' => $key, 'faces' => []];
            $edgeMap[$key]['faces'][] = $index;
        }
    }
    $edges = array_keys($edgeMap);
    usort($edges, fn($x, $y) => ($edgeMap[$x]['a'] <=> $edgeMap[$y]['a']) ?: ($edgeMap[$x]['b'] <=> $edgeMap[$y]['b']));
    $vertexEdges = [];
    $parents = [];
    foreach ($faces as $index => $_) $parents[$index] = $index;
    foreach ($edges as $key) {
        $edge = $edgeMap[$key];
        $vertexEdges[$edge['a']][] = $key;
        $vertexEdges[$edge['b']][] = $key;
        for ($i = 1; $i < count($edge['faces']); $i++) joinRoots($parents, $edge['faces'][0], $edge['faces'][$i]);
    }
    $components = [];
    $roots = [];
    $componentOf = [];
    foreach ($faces as $index => $face) {
        $root = findRoot($parents, $index);
        if (!isset($roots[$root])) {
            $roots[$root] = count($components);
            $components[] = ['number' => count($components) + 1, 'faces' => [], 'edges' => [], 'vertexSet' => []];
        }
        $componentIndex = $roots[$root];
        $components[$componentIndex]['faces'][] = $index;
        $componentOf[$index] = $componentIndex + 1;
        foreach ($face['vertices'] as $vertex) $components[$componentIndex]['vertexSet'][$vertex] = true;
    }
    foreach ($components as &$component) {
        $component['vertices'] = array_keys($component['vertexSet']);
        sort($component['vertices'], SORT_NUMERIC);
    }
    unset($component);
    foreach ($edges as $key) {
        $componentIndex = $componentOf[$edgeMap[$key]['faces'][0]] - 1;
        $components[$componentIndex]['edges'][] = $key;
    }
    $fans = [];
    foreach ($vertexFaces as $vertex => $incident) {
        $local = [];
        foreach ($incident as $index) $local[$index] = $index;
        foreach ($vertexEdges[$vertex] as $key) {
            $edge = $edgeMap[$key];
            for ($i = 1; $i < count($edge['faces']); $i++) joinRoots($local, $edge['faces'][0], $edge['faces'][$i]);
        }
        $parts = [];
        foreach ($incident as $index) $parts[findRoot($local, $index)][] = $index;
        $fans[$vertex] = array_values($parts);
    }
    return compact('edgeMap', 'edges', 'vertexEdges', 'vertexFaces', 'components', 'componentOf', 'fans');
}

function boundaryLoops(array $topology): array
{
    $loops = [];
    foreach ($topology['components'] as $component) {
        $boundary = [];
        $unused = [];
        $incident = [];
        foreach ($component['edges'] as $key) {
            $edge = $topology['edgeMap'][$key];
            if (count($edge['faces']) !== 1) continue;
            $boundary[] = $key;
            $unused[$key] = true;
            $incident[$edge['a']][] = $key;
            $incident[$edge['b']][] = $key;
        }
        foreach ($incident as $vertex => &$keys) {
            usort($keys, function ($x, $y) use ($vertex, $topology) {
                $a = $topology['edgeMap'][$x];
                $b = $topology['edgeMap'][$y];
                $otherA = $a['a'] === $vertex ? $a['b'] : $a['a'];
                $otherB = $b['a'] === $vertex ? $b['b'] : $b['a'];
                return $otherA <=> $otherB;
            });
        }
        unset($keys);
        foreach ($boundary as $key) {
            if (!isset($unused[$key])) continue;
            unset($unused[$key]);
            $edge = $topology['edgeMap'][$key];
            $sequence = [$edge['a'], $edge['b']];
            while ($sequence[count($sequence) - 1] !== $sequence[0]) {
                $current = $sequence[count($sequence) - 1];
                $next = null;
                foreach ($incident[$current] as $candidate) {
                    if (isset($unused[$candidate])) {
                        $next = $candidate;
                        break;
                    }
                }
                if ($next === null) break;
                unset($unused[$next]);
                $edge = $topology['edgeMap'][$next];
                $sequence[] = $edge['a'] === $current ? $edge['b'] : $edge['a'];
            }
            $closed = $sequence[count($sequence) - 1] === $sequence[0];
            $length = count($sequence) - 1;
            if ($closed) array_pop($sequence);
            $loops[] = ['number' => count($loops) + 1, 'component' => $component['number'],
                'vertices' => $sequence, 'closed' => $closed, 'length' => $length];
        }
    }
    return $loops;
}
