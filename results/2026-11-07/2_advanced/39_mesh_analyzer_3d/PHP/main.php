<?php

require_once __DIR__ . '/obj_io.php';
require_once __DIR__ . '/topology.php';
require_once __DIR__ . '/orientation.php';
require_once __DIR__ . '/measure.php';
require_once __DIR__ . '/repair.php';

function listText(array $values): string
{
    return $values ? implode(' ', $values) : '-';
}

function yesNo(bool $value): string
{
    return $value ? 'yes' : 'no';
}

function uniqueSorted(array $values): array
{
    $values = array_values(array_unique($values));
    sort($values, SORT_NUMERIC);
    return $values;
}

function readParameters(): array
{
    $settings = ['snap' => 1, 'merge' => true, 'degenerate' => true, 'duplicates' => true,
        'orient' => true, 'outward' => true, 'fill_holes' => 0, 'keep_unused' => true,
        'sections' => ['summary', 'components'], 'queries' => []];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        if ($line === '' || $line[0] === '#') continue;
        $values = explode(' ', $line);
        $name = array_shift($values);
        if ($name === 'query') {
            $kind = array_shift($values);
            $settings['queries'][] = ['kind' => $kind, 'values' => array_map('intval', $values)];
        } elseif ($name === 'sections') {
            $settings['sections'] = $values;
        } elseif ($name === 'snap' || $name === 'fill_holes') {
            $settings[$name] = (int)$values[0];
        } else {
            $settings[$name] = $values[0] === 'on';
        }
    }
    return $settings;
}

function isNonplanar(array $polygon, array $positions): bool
{
    $points = array_map(fn($v) => $positions[$v], $polygon['vertices']);
    $n = [0, 0, 0];
    for ($i = 1; $i < count($points) - 1; $i++) {
        $n = vectorAdd($n, cross(difference($points[$i], $points[0]), difference($points[$i + 1], $points[0])));
    }
    foreach ($points as $point) if (dot(difference($point, $points[0]), $n) !== 0) return true;
    return false;
}

function cleanup(array &$model, array $settings): array
{
    $triangles = triangulate($model['polygons']);
    $snapped = snapVertices($model['vertices'], $settings['snap']);
    $representatives = representatives($snapped['positions'], $settings['merge']);
    $removal = removeTriangles($triangles, $representatives['numbers'], $snapped['positions'], $settings);
    $used = [];
    foreach ($removal['faces'] as $face) foreach ($face['vertices'] as $vertex) $used[$vertex] = true;
    $originalToNew = [];
    $vertices = [null];
    for ($original = 1; $original < count($model['vertices']); $original++) {
        $output = $settings['keep_unused'] ? $representatives['numbers'][$original] === $original : isset($used[$original]);
        if (!$output) continue;
        $originalToNew[$original] = count($vertices);
        $vertices[] = $snapped['positions'][$original];
    }
    $faces = [];
    foreach ($removal['faces'] as $face) {
        $face['vertices'] = array_map(fn($v) => $originalToNew[$v], $face['vertices']);
        $face['initial'] = $face['vertices'];
        $faces[] = $face;
    }
    $polygonSizes = [];
    foreach ($model['polygons'] as &$polygon) {
        $polygon['nonplanar'] = isNonplanar($polygon, $snapped['positions']);
        $size = count($polygon['vertices']);
        $polygonSizes[$size] = ($polygonSizes[$size] ?? 0) + 1;
    }
    unset($polygon);
    ksort($polygonSizes, SORT_NUMERIC);
    return ['triangles' => $triangles, 'snapped' => $snapped, 'representatives' => $representatives,
        'removed' => $removal['removed'], 'originalToNew' => $originalToNew, 'vertices' => $vertices,
        'faces' => $faces, 'polygonSizes' => $polygonSizes];
}

function coherentLoops(array $faces, array $topology): array
{
    $loops = boundaryLoops($topology);
    foreach ($loops as &$loop) {
        $loop['kind'] = 'open';
        if (!$loop['closed']) continue;
        $agreeing = 0;
        for ($i = 0; $i < $loop['length']; $i++) {
            $a = $loop['vertices'][$i];
            $b = $loop['vertices'][($i + 1) % $loop['length']];
            $edge = $topology['edgeMap'][edgeKey($a, $b)];
            if (containsDirection($faces[$edge['faces'][0]], $a, $b)) $agreeing++;
        }
        $loop['kind'] = $agreeing === 0 || $agreeing === $loop['length'] ? 'coherent' : 'mixed';
        if ($agreeing === 0) $loop['vertices'] = array_merge([$loop['vertices'][0]], array_reverse(array_slice($loop['vertices'], 1)));
    }
    unset($loop);
    return $loops;
}

function prepareAndFill(array &$faces, array $settings): array
{
    $originalFaces = count($faces);
    $topology = analyze($faces);
    $inconsistentBefore = count(inconsistentEdges($faces, $topology));
    if ($settings['orient']) orientFaces($faces, $topology);
    $inconsistent = inconsistentEdges($faces, $topology);
    $loops = coherentLoops($faces, $topology);
    $blocked = [];
    foreach ($topology['edges'] as $key) {
        $edge = $topology['edgeMap'][$key];
        if (count($edge['faces']) >= 3) $blocked[$topology['componentOf'][$edge['faces'][0]]] = true;
    }
    foreach ($inconsistent as $key) {
        $edge = $topology['edgeMap'][$key];
        $blocked[$topology['componentOf'][$edge['faces'][0]]] = true;
    }
    $filled = 0;
    foreach ($loops as &$loop) {
        $loop['filled'] = $loop['kind'] === 'coherent' && $loop['length'] >= 3 &&
            $loop['length'] <= $settings['fill_holes'] && count(array_unique($loop['vertices'])) === $loop['length'] &&
            !isset($blocked[$loop['component']]);
        if ($loop['filled']) {
            $filled++;
            foreach (fillTriangles($loop) as $face) $faces[] = $face;
        }
    }
    unset($loop);
    return compact('topology', 'inconsistent', 'loops', 'inconsistentBefore', 'originalFaces', 'filled') +
        ['fillFaces' => count($faces) - $originalFaces];
}

function componentProperties(array $faces, array &$topology): void
{
    $loops = coherentLoops($faces, $topology);
    $inconsistent = array_fill_keys(inconsistentEdges($faces, $topology), true);
    foreach ($topology['components'] as &$component) {
        $component['boundary'] = [];
        $component['nonmanifoldEdges'] = [];
        $component['nonmanifoldVertices'] = [];
        foreach ($component['edges'] as $key) {
            $count = count($topology['edgeMap'][$key]['faces']);
            if ($count === 1) $component['boundary'][] = $key;
            if ($count >= 3) $component['nonmanifoldEdges'][] = $key;
        }
        $component['loopCount'] = count(array_filter($loops, fn($loop) => $loop['component'] === $component['number']));
        $component['closed'] = count($component['boundary']) === 0;
        $component['consistent'] = true;
        foreach ($component['edges'] as $key) if (isset($inconsistent[$key])) $component['consistent'] = false;
        $component['chi'] = count($component['vertices']) - count($component['edges']) + count($component['faces']);
        $component['inside'] = [];
    }
    unset($component);
    foreach ($topology['fans'] as $vertex => $fans) {
        $counts = [];
        foreach ($fans as $fan) {
            $number = $topology['componentOf'][$fan[0]];
            $counts[$number] = ($counts[$number] ?? 0) + 1;
        }
        foreach ($counts as $number => $count) {
            if ($count >= 2) $topology['components'][$number - 1]['nonmanifoldVertices'][] = $vertex;
        }
    }
    foreach ($topology['components'] as &$component) {
        $component['manifold'] = !$component['nonmanifoldEdges'] && !$component['nonmanifoldVertices'];
        $component['solid'] = $component['closed'] && $component['manifold'] && $component['consistent'];
    }
    unset($component);
}

function nestAndOrient(array &$faces, array $vertices, array &$topology, array $settings): int
{
    foreach ($topology['components'] as $i => $component) {
        if (!$component['solid']) continue;
        foreach ($topology['components'] as $j => $other) {
            if ($i === $j || !$other['solid']) continue;
            $vertex = null;
            foreach ($component['vertices'] as $v) {
                if (!isset($other['vertexSet'][$v])) {
                    $vertex = $v;
                    break;
                }
            }
            if ($vertex !== null && winding($faces, $vertices, $other['faces'], $vertices[$vertex]) !== 0) {
                $topology['components'][$i]['inside'][] = $other['number'];
            }
        }
    }
    $outwardComponents = 0;
    if ($settings['outward']) {
        foreach ($topology['components'] as $component) {
            if (!$component['solid']) continue;
            $volume = volume6($faces, $vertices, $component['faces']);
            $reverse = count($component['inside']) % 2 === 0 ? $volume < 0 : $volume > 0;
            if ($volume !== 0 && $reverse) {
                foreach ($component['faces'] as $index) flipFace($faces[$index]);
                $outwardComponents++;
            }
        }
    }
    $copy = [];
    foreach ($faces as $face) $copy[] = ['vertices' => array_values($face['vertices'])];
    orientFaces($copy, $topology);
    $inconsistent = array_fill_keys(inconsistentEdges($copy, $topology), true);
    foreach ($topology['components'] as &$component) {
        $component['orientable'] = true;
        foreach ($component['edges'] as $key) if (isset($inconsistent[$key])) $component['orientable'] = false;
        $component['genus'] = $component['manifold'] && $component['orientable']
            ? intdiv(2 - $component['chi'] - $component['loopCount'], 2) : null;
        $component['crosscaps'] = $component['manifold'] && !$component['orientable']
            ? 2 - $component['chi'] - $component['loopCount'] : null;
    }
    unset($component);
    return $outwardComponents;
}

function measureEdges(array $faces, array $vertices, array &$topology, array $geometry): void
{
    foreach ($topology['edges'] as $key) {
        $edge = &$topology['edgeMap'][$key];
        $delta = difference($vertices[$edge['a']], $vertices[$edge['b']]);
        $edge['len2'] = dot($delta, $delta);
        $count = count($edge['faces']);
        $edge['kind'] = $count === 1 ? 'boundary' : ($count === 2 ? 'manifold' : 'nonmanifold');
        $edge['shape'] = null;
        if ($count === 2) {
            [$f, $g] = $edge['faces'];
            if (containsDirection($faces[$f], $edge['a'], $edge['b']) === containsDirection($faces[$g], $edge['a'], $edge['b'])) {
                $edge['shape'] = 'inconsistent';
            } else {
                foreach ($faces[$g]['vertices'] as $v) if ($v !== $edge['a'] && $v !== $edge['b']) $opposite = $v;
                $side = dot(difference($vertices[$opposite], $vertices[$faces[$f]['vertices'][0]]), $geometry[$f]['normal']);
                $edge['shape'] = $side < 0 ? 'convex' : ($side > 0 ? 'concave' : 'flat');
            }
        }
        unset($edge);
    }
}

function measureComponents(array $faces, array $vertices, array &$topology, array $geometry, array $groups): void
{
    foreach ($topology['components'] as &$component) {
        $groupNames = array_map(fn($i) => $faces[$i]['group'], $component['faces']);
        $component['groups'] = array_values(array_filter($groups, fn($group) => in_array($group, $groupNames, true)));
        $component['area'] = meshArea($geometry, $component['faces']);
        $component['volume6'] = 0;
        $component['normalSum'] = [0, 0, 0];
        $component['angles'] = ['acute' => 0, 'right' => 0, 'obtuse' => 0];
        foreach ($component['faces'] as $index) {
            $component['volume6'] += $geometry[$index]['determinant'];
            $component['normalSum'] = vectorAdd($component['normalSum'], $geometry[$index]['normal']);
            $component['angles'][$geometry[$index]['angle']]++;
        }
        $component['centroid'] = $component['solid'] && $component['volume6'] !== 0
            ? centroid($faces, $vertices, $component['faces'], $geometry, $component['volume6']) : null;
        $component['minimum'] = $vertices[$component['vertices'][0]];
        $component['maximum'] = $vertices[$component['vertices'][0]];
        foreach ($component['vertices'] as $vertex) {
            for ($k = 0; $k < 3; $k++) {
                $component['minimum'][$k] = min($component['minimum'][$k], $vertices[$vertex][$k]);
                $component['maximum'][$k] = max($component['maximum'][$k], $vertices[$vertex][$k]);
            }
        }
        $component['shapes'] = ['convex' => 0, 'concave' => 0, 'flat' => 0];
        $degrees = array_fill_keys($component['vertices'], 0);
        $lengths = [];
        foreach ($component['edges'] as $key) {
            $edge = $topology['edgeMap'][$key];
            if ($edge['shape'] !== null && isset($component['shapes'][$edge['shape']])) $component['shapes'][$edge['shape']]++;
            $degrees[$edge['a']]++;
            $degrees[$edge['b']]++;
            $lengths[] = $edge['len2'];
        }
        $component['minDegree'] = min($degrees);
        $component['maxDegree'] = max($degrees);
        $component['minLength'] = min($lengths);
        $component['maxLength'] = max($lengths);
    }
    unset($component);
}

function boundaryReport(array $before): array
{
    $topology = $before['topology'];
    $lines = ['loops ' . count($before['loops'])];
    foreach ($before['loops'] as $loop) {
        $lines[] = 'loop ' . $loop['number'] . ' component ' . $loop['component'] . ' length ' . $loop['length'] .
            ' ' . $loop['kind'] . ' ' . ($loop['filled'] ? 'filled' : 'kept') . ' vertices ' . listText($loop['vertices']);
    }
    $nonmanifoldEdges = array_values(array_filter($topology['edges'], fn($key) => count($topology['edgeMap'][$key]['faces']) >= 3));
    $lines[] = 'nonmanifold_edges ' . count($nonmanifoldEdges);
    foreach ($nonmanifoldEdges as $key) {
        $edge = $topology['edgeMap'][$key];
        $numbers = array_map(fn($i) => $i + 1, $edge['faces']);
        $lines[] = 'edge ' . $edge['a'] . ' ' . $edge['b'] . ' faces ' . listText($numbers);
    }
    $vertices = array_keys(array_filter($topology['fans'], fn($fans) => count($fans) >= 2));
    sort($vertices, SORT_NUMERIC);
    $lines[] = 'nonmanifold_vertices ' . count($vertices);
    foreach ($vertices as $vertex) {
        $fans = $topology['fans'][$vertex];
        $components = uniqueSorted(array_map(fn($fan) => $topology['componentOf'][$fan[0]], $fans));
        $lines[] = 'vertex ' . $vertex . ' fans ' . count($fans) . ' components ' . listText($components);
    }
    $lines[] = 'inconsistent_edges ' . count($before['inconsistent']);
    foreach ($before['inconsistent'] as $key) {
        $edge = $topology['edgeMap'][$key];
        $numbers = array_map(fn($i) => $i + 1, $edge['faces']);
        $lines[] = 'edge ' . $edge['a'] . ' ' . $edge['b'] . ' faces ' . listText($numbers);
    }
    return $lines;
}

function vertexQuery(int $value, array $context): string
{
    $topology = $context['topology'];
    if ($value < 1 || $value >= count($context['vertices'])) return 'vertex ' . $value . ' invalid';
    $faces = $topology['vertexFaces'][$value] ?? [];
    $edges = $topology['vertexEdges'][$value] ?? [];
    $fans = $topology['fans'][$value] ?? [];
    $components = uniqueSorted(array_map(fn($i) => $topology['componentOf'][$i], $faces));
    $boundary = false;
    foreach ($edges as $key) if (count($topology['edgeMap'][$key]['faces']) === 1) $boundary = true;
    return 'vertex ' . $value . ' at ' . implode(' ', $context['vertices'][$value]) . ' faces ' . count($faces) .
        ' valence ' . count($edges) . ' fans ' . count($fans) . ' boundary ' . yesNo($boundary) . ' components ' . listText($components);
}

function faceQuery(int $value, array $context): string
{
    if ($value < 1 || $value > count($context['faces'])) return 'face ' . $value . ' invalid';
    $index = $value - 1;
    $face = $context['faces'][$index];
    $topology = $context['topology'];
    $neighbors = [];
    for ($i = 0; $i < 3; $i++) {
        $edge = $topology['edgeMap'][edgeKey($face['vertices'][$i], $face['vertices'][($i + 1) % 3])];
        $count = count($edge['faces']);
        $neighbors[] = $count === 1 ? '-' : ($count >= 3 ? '*' :
            ($edge['faces'][0] === $index ? $edge['faces'][1] + 1 : $edge['faces'][0] + 1));
    }
    $polygon = $face['polygon']['number'] ?? '-';
    $line = $face['polygon']['line'] ?? '-';
    $geometry = $context['geometry'][$index];
    return 'face ' . $value . ' vertices ' . implode(' ', $face['vertices']) . ' group ' . $face['group'] .
        ' polygon ' . $polygon . ' line ' . $line . ' component ' . $topology['componentOf'][$index] .
        ' normal ' . implode(' ', $geometry['normal']) . ' area ' . realNumber(sqrt($geometry['q']) / 2) .
        ' neighbors ' . implode(' ', $neighbors);
}

function edgeQuery(int $first, int $second, array $context): string
{
    $a = min($first, $second);
    $b = max($first, $second);
    $edge = $context['topology']['edgeMap'][edgeKey($a, $b)] ?? null;
    if ($edge === null) return 'edge ' . $a . ' ' . $b . ' none';
    $numbers = array_map(fn($i) => $i + 1, $edge['faces']);
    return 'edge ' . $a . ' ' . $b . ' faces ' . listText($numbers) . ' kind ' . $edge['kind'] .
        ' shape ' . ($edge['shape'] ?? '-') . ' len2 ' . $edge['len2'];
}

function pointQuery(array $point, array $context): string
{
    $inside = [];
    $total = 0;
    foreach ($context['topology']['components'] as $component) {
        if (!$component['solid']) continue;
        $number = winding($context['faces'], $context['vertices'], $component['faces'], $point);
        if ($number !== 0) $inside[] = $component['number'];
        $total += $number;
    }
    return 'point ' . implode(' ', $point) . ' inside ' . listText($inside) . ' winding ' . $total;
}

function pathQuery(int $first, int $last, array $context): string
{
    $count = count($context['vertices']);
    if ($first < 1 || $first >= $count || $last < 1 || $last >= $count) return 'path ' . $first . ' ' . $last . ' invalid';
    $topology = $context['topology'];
    $parent = array_fill(0, $count, null);
    $parent[$first] = $first;
    $queue = [$first];
    for ($head = 0; $head < count($queue); $head++) {
        $vertex = $queue[$head];
        $neighbors = [];
        foreach ($topology['vertexEdges'][$vertex] ?? [] as $key) {
            $edge = $topology['edgeMap'][$key];
            $neighbors[] = $edge['a'] === $vertex ? $edge['b'] : $edge['a'];
        }
        sort($neighbors, SORT_NUMERIC);
        foreach ($neighbors as $next) {
            if ($parent[$next] !== null) continue;
            $parent[$next] = $vertex;
            $queue[] = $next;
        }
    }
    if ($parent[$last] === null) return 'path ' . $first . ' ' . $last . ' none';
    $path = [$last];
    while ($path[count($path) - 1] !== $first) $path[] = $parent[$path[count($path) - 1]];
    $path = array_reverse($path);
    return 'path ' . $first . ' ' . $last . ' hops ' . (count($path) - 1) . ' vertices ' . listText($path);
}

function viewQuery(array $direction, array $context): string
{
    $sides = array_map(fn($g) => dot($g['normal'], $direction), $context['geometry']);
    $front = $back = $side = $silhouette = 0;
    foreach ($sides as $value) {
        if ($value > 0) $front++;
        elseif ($value < 0) $back++;
        else $side++;
    }
    foreach ($context['topology']['edges'] as $key) {
        $edge = $context['topology']['edgeMap'][$key];
        if (count($edge['faces']) !== 2) continue;
        [$a, $b] = $edge['faces'];
        if (($sides[$a] > 0 && $sides[$b] < 0) || ($sides[$a] < 0 && $sides[$b] > 0)) $silhouette++;
    }
    return 'view ' . implode(' ', $direction) . ' front ' . $front . ' back ' . $back .
        ' side ' . $side . ' silhouette ' . $silhouette;
}

function queryReport(array $context): array
{
    $lines = ['[queries]'];
    foreach ($context['settings']['queries'] as $query) {
        $values = $query['values'];
        switch ($query['kind']) {
            case 'vertex': $lines[] = vertexQuery($values[0], $context); break;
            case 'face': $lines[] = faceQuery($values[0], $context); break;
            case 'edge': $lines[] = edgeQuery($values[0], $values[1], $context); break;
            case 'point': $lines[] = pointQuery($values, $context); break;
            case 'path': $lines[] = pathQuery($values[0], $values[1], $context); break;
            case 'view': $lines[] = viewQuery($values, $context); break;
        }
    }
    return $lines;
}

function summaryReport(array $context): array
{
    $model = $context['model'];
    $clean = $context['clean'];
    $before = $context['before'];
    $components = $context['topology']['components'];
    $solids = array_filter($components, fn($component) => $component['solid']);
    $totalVolume = 0;
    foreach ($solids as $component) $totalVolume += $component['volume6'];
    $lines = ['[summary]', 'lines ' . $model['lines'], 'vertices ' . (count($model['vertices']) - 1),
        'polygons ' . count($model['polygons']), 'errors ' . count($model['errors']), 'ignored ' . $model['ignored'],
        'nonplanar_polygons ' . count(array_filter($model['polygons'], fn($polygon) => $polygon['nonplanar']))];
    foreach ($clean['polygonSizes'] as $size => $count) $lines[] = 'polygon_size ' . $size . ' ' . $count;
    $lines[] = 'triangles ' . count($clean['triangles']);
    $lines[] = 'snapped ' . count($clean['snapped']['changed']);
    $lines[] = 'merged ' . $clean['representatives']['merged'];
    foreach (['repeated', 'zero_area', 'duplicate'] as $reason) {
        $lines[] = 'removed_' . $reason . ' ' . count(array_filter($clean['removed'], fn($item) => $item['reason'] === $reason));
    }
    $lines[] = 'faces ' . $before['originalFaces'];
    $lines[] = 'inconsistent_before ' . $before['inconsistentBefore'];
    $lines[] = 'flipped_faces ' . $context['flippedFaces'];
    $lines[] = 'outward_components ' . $context['outwardComponents'];
    $lines[] = 'boundary_loops ' . count($before['loops']);
    $lines[] = 'holes_filled ' . $before['filled'];
    $lines[] = 'fill_faces ' . $before['fillFaces'];
    $lines[] = 'final_vertices ' . (count($context['vertices']) - 1);
    $lines[] = 'final_faces ' . count($context['faces']);
    $lines[] = 'components ' . count($components);
    $lines[] = 'solids ' . count($solids);
    $lines[] = 'total_area ' . realNumber(meshArea($context['geometry'], array_keys($context['geometry'])));
    $lines[] = 'total_volume ' . fraction($totalVolume, 6);
    return $lines;
}

function warningReport(array $context): array
{
    $lines = ['[warnings]'];
    foreach ($context['model']['errors'] as $error) $lines[] = 'line ' . $error['line'] . ' ' . $error['kind'];
    return $lines;
}

function cleanupReport(array $context): array
{
    $clean = $context['clean'];
    $lines = ['[cleanup]', 'snapped ' . count($clean['snapped']['changed'])];
    foreach ($clean['snapped']['changed'] as $item) {
        $lines[] = 'snap ' . $item['original'] . ' ' . implode(' ', $item['before']) . ' to ' . implode(' ', $item['after']);
    }
    $lines[] = 'merged ' . $clean['representatives']['merged'];
    foreach ($clean['representatives']['groups'] as $representative => $members) {
        if (count($members) >= 2) $lines[] = 'merge ' . ($clean['originalToNew'][$representative] ?? '-') . ' ' . listText($members);
    }
    $lines[] = 'removed ' . count($clean['removed']);
    foreach ($clean['removed'] as $item) {
        $triangle = $item['triangle'];
        $lines[] = 'remove ' . $triangle['number'] . ' polygon ' . $triangle['polygon']['number'] .
            ' line ' . $triangle['polygon']['line'] . ' ' . $item['reason'];
    }
    return $lines;
}

function componentReport(array $context): array
{
    $lines = [];
    foreach ($context['topology']['components'] as $component) {
        $lines[] = '[component ' . $component['number'] . ']';
        $lines[] = 'groups ' . listText($component['groups']);
        $lines[] = 'faces ' . count($component['faces']);
        $lines[] = 'vertices ' . count($component['vertices']);
        $lines[] = 'edges ' . count($component['edges']);
        $lines[] = 'boundary_edges ' . count($component['boundary']);
        $lines[] = 'nonmanifold_edges ' . count($component['nonmanifoldEdges']);
        $lines[] = 'nonmanifold_vertices ' . count($component['nonmanifoldVertices']);
        $lines[] = 'boundary_loops ' . $component['loopCount'];
        $lines[] = 'closed ' . yesNo($component['closed']);
        $lines[] = 'manifold ' . yesNo($component['manifold']);
        $lines[] = 'orientable ' . yesNo($component['orientable']);
        $lines[] = 'consistent ' . yesNo($component['consistent']);
        $lines[] = 'solid ' . yesNo($component['solid']);
        $lines[] = 'euler ' . $component['chi'];
        if (!$component['manifold']) $lines[] = 'genus -';
        elseif ($component['orientable']) $lines[] = 'genus ' . $component['genus'];
        else $lines[] = 'crosscaps ' . $component['crosscaps'];
        $lines[] = 'volume ' . ($component['solid'] ? fraction($component['volume6'], 6) : '-');
        $lines[] = 'area ' . realNumber($component['area']);
        $lines[] = 'normal_sum ' . implode(' ', $component['normalSum']);
        $lines[] = 'bbox ' . implode(' ', array_merge($component['minimum'], $component['maximum']));
        $lines[] = 'inside ' . ($component['solid'] ? listText($component['inside']) : '-');
        $lines[] = 'centroid ' . ($component['centroid'] === null ? '-' : implode(' ', $component['centroid']));
        foreach (['convex', 'concave', 'flat'] as $shape) $lines[] = $shape . ' ' . $component['shapes'][$shape];
        foreach (['acute', 'right', 'obtuse'] as $angle) $lines[] = $angle . ' ' . $component['angles'][$angle];
        $lines[] = 'edge_len2 ' . $component['minLength'] . ' ' . $component['maxLength'];
        $lines[] = 'valence ' . $component['minDegree'] . ' ' . $component['maxDegree'];
    }
    return $lines;
}

function groupReport(array $context): array
{
    $lines = [];
    foreach ($context['groups'] as $group) {
        $polygons = array_filter($context['model']['polygons'], fn($polygon) => $polygon['group'] === $group);
        $triangles = array_filter($context['clean']['triangles'], fn($triangle) => $triangle['polygon']['group'] === $group);
        $indices = [];
        foreach ($context['faces'] as $index => $face) if ($face['group'] === $group) $indices[] = $index;
        $components = uniqueSorted(array_map(fn($i) => $context['topology']['componentOf'][$i], $indices));
        $lines[] = '[group ' . $group . ']';
        $lines[] = 'polygons ' . count($polygons);
        $lines[] = 'triangles ' . count($triangles);
        $lines[] = 'nonplanar ' . count(array_filter($polygons, fn($polygon) => $polygon['nonplanar']));
        $lines[] = 'faces ' . count($indices);
        $lines[] = 'area ' . realNumber(meshArea($context['geometry'], $indices));
        $lines[] = 'components ' . listText($components);
    }
    return $lines;
}

function contactReport(array $context): array
{
    $lines = ['[contacts]'];
    $components = $context['topology']['components'];
    $vertices = $context['vertices'];
    for ($i = 0; $i < count($components); $i++) {
        $first = $components[$i];
        for ($j = $i + 1; $j < count($components); $j++) {
            $second = $components[$j];
            $intersect = true;
            for ($k = 0; $k < 3; $k++) {
                if ($first['minimum'][$k] > $second['maximum'][$k] || $second['minimum'][$k] > $first['maximum'][$k]) $intersect = false;
            }
            if (!$intersect) continue;
            $shared = 0;
            foreach ($first['vertices'] as $vertex) if (isset($second['vertexSet'][$vertex])) $shared++;
            $gap = null;
            foreach ($first['vertices'] as $a) {
                foreach ($second['vertices'] as $b) {
                    if ($a === $b) continue;
                    $delta = difference($vertices[$a], $vertices[$b]);
                    $distance = dot($delta, $delta);
                    if ($gap === null || $distance < $gap) $gap = $distance;
                }
            }
            $lines[] = 'contact ' . $first['number'] . ' ' . $second['number'] . ' shared ' . $shared . ' gap2 ' . $gap;
        }
    }
    return $lines;
}

function edgeReport(array $context): array
{
    $topology = $context['topology'];
    $lines = ['[edges]', 'edges ' . count($topology['edges'])];
    $kinds = ['boundary' => 0, 'manifold' => 0, 'nonmanifold' => 0];
    $shapes = ['convex' => 0, 'concave' => 0, 'flat' => 0, 'inconsistent' => 0];
    $maximum = 0;
    $shortest = null;
    $longest = null;
    foreach ($topology['edges'] as $key) {
        $edge = $topology['edgeMap'][$key];
        $kinds[$edge['kind']]++;
        if ($edge['shape'] !== null) $shapes[$edge['shape']]++;
        $maximum = max($maximum, count($edge['faces']));
        if ($shortest === null || $edge['len2'] < $shortest['len2']) $shortest = $edge;
        if ($longest === null || $edge['len2'] > $longest['len2']) $longest = $edge;
    }
    foreach ($kinds as $kind => $count) $lines[] = $kind . ' ' . $count;
    $lines[] = 'max_faces ' . $maximum;
    foreach ($shapes as $shape => $count) $lines[] = $shape . ' ' . $count;
    $lines[] = 'shortest ' . $shortest['a'] . ' ' . $shortest['b'] . ' len2 ' . $shortest['len2'];
    $lines[] = 'longest ' . $longest['a'] . ' ' . $longest['b'] . ' len2 ' . $longest['len2'];
    return $lines;
}

function valenceReport(array $context): array
{
    $degrees = array_map('count', $context['topology']['vertexEdges']);
    $histogram = [];
    $total = 0;
    foreach ($degrees as $degree) {
        $histogram[$degree] = ($histogram[$degree] ?? 0) + 1;
        $total += $degree;
    }
    ksort($histogram, SORT_NUMERIC);
    $lines = ['[valence]', 'used ' . count($degrees), 'isolated ' . (count($context['vertices']) - 1 - count($degrees)),
        'min ' . min($degrees), 'max ' . max($degrees), 'mean ' . fraction($total, count($degrees))];
    foreach ($histogram as $degree => $count) $lines[] = 'degree ' . $degree . ' ' . $count;
    return $lines;
}

function componentsCsv(array $context): array
{
    $lines = ['component,faces,vertices,closed,euler,genus,volume6,area'];
    foreach ($context['topology']['components'] as $component) {
        $lines[] = implode(',', [$component['number'], count($component['faces']), count($component['vertices']),
            yesNo($component['closed']), $component['chi'], $component['genus'] ?? '-',
            $component['solid'] ? $component['volume6'] : '-', realNumber($component['area'])]);
    }
    return $lines;
}

function writeLines(string $name, array $lines): void
{
    file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}

function main(): void
{
    $settings = readParameters();
    $model = readModel();
    $clean = cleanup($model, $settings);
    $vertices = $clean['vertices'];
    $faces = $clean['faces'];
    $before = prepareAndFill($faces, $settings);
    $groups = $model['groups'];
    if ($before['fillFaces'] > 0) $groups[] = 'fill';
    $boundaries = boundaryReport($before);
    $topology = analyze($faces);
    componentProperties($faces, $topology);
    $outwardComponents = nestAndOrient($faces, $vertices, $topology, $settings);
    $geometry = array_map(fn($face) => faceGeometry($face, $vertices), $faces);
    measureEdges($faces, $vertices, $topology, $geometry);
    measureComponents($faces, $vertices, $topology, $geometry, $groups);
    $flippedFaces = 0;
    for ($i = 0; $i < $before['originalFaces']; $i++) {
        if ($faces[$i]['vertices'] !== $faces[$i]['initial']) $flippedFaces++;
    }
    $context = compact('settings', 'model', 'clean', 'before', 'groups', 'vertices', 'faces', 'topology', 'geometry',
        'outwardComponents', 'flippedFaces');
    $sections = ['summary' => 'summaryReport', 'warnings' => 'warningReport', 'cleanup' => 'cleanupReport',
        'components' => 'componentReport', 'groups' => 'groupReport', 'contacts' => 'contactReport',
        'edges' => 'edgeReport', 'valence' => 'valenceReport', 'queries' => 'queryReport'];
    $report = [];
    foreach ($settings['sections'] as $name) $report = array_merge($report, $sections[$name]($context));
    if (!is_dir('output')) mkdir('output', 0777, true);
    writeLines('report.txt', $report);
    writeLines('components.csv', componentsCsv($context));
    writeLines('boundaries.txt', $boundaries);
    writeModel($vertices, $faces);
}

main();
