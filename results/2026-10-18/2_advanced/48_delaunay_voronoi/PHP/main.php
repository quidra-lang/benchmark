<?php

require_once __DIR__ . '/predicates.php';
require_once __DIR__ . '/triangulation.php';
require_once __DIR__ . '/voronoi.php';
require_once __DIR__ . '/proximity.php';
require_once __DIR__ . '/plot.php';

function joined($values)
{
    return implode(' ', $values);
}

function edgeKey($a, $b)
{
    return keyOf(min($a, $b), max($a, $b));
}

function yesNo($value)
{
    return $value ? 'yes' : 'no';
}

function fixed($value)
{
    $text = number_format(abs($value), 3, '.', '');
    return $value < 0 && $text !== '0.000' ? '-' . $text : $text;
}

function readInput()
{
    $raw = file('input/points.txt', FILE_IGNORE_NEW_LINES);
    $points = [null];
    $errors = [];
    $seen = [];
    foreach ($raw as $index => $line) {
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        $words = explode(' ', $line);
        if (count($words) !== 2 || !preg_match('/^-?[0-9]+$/D', $words[0]) || !preg_match('/^-?[0-9]+$/D', $words[1])) {
            $errors[] = 'reject ' . ($index + 1) . ' format';
            continue;
        }
        $x = (int)$words[0];
        $y = (int)$words[1];
        if ($x < 0 || $x > 1000 || $y < 0 || $y > 1000) {
            $errors[] = 'reject ' . ($index + 1) . ' range';
            continue;
        }
        $coordinate = keyOf($x, $y);
        if (isset($seen[$coordinate])) {
            $errors[] = 'reject ' . ($index + 1) . ' duplicate ' . $seen[$coordinate];
            continue;
        }
        $seen[$coordinate] = count($points);
        $points[] = ['x' => $x, 'y' => $y];
    }
    $parameters = ['plot' => [61, 31], 'layers' => ['edges', 'hull', 'sites'],
        'sections' => ['summary'], 'alpha' => [], 'queries' => []];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        $words = explode(' ', $line);
        $name = array_shift($words);
        if ($name === 'query') {
            $kind = array_shift($words);
            $parameters['queries'][] = ['text' => substr($line, 6), 'kind' => $kind, 'values' => array_map('intval', $words)];
        } elseif ($name === 'plot') {
            $parameters['plot'] = array_map('intval', $words);
        } elseif ($name === 'plot_layers') {
            $parameters['layers'] = $words;
        } elseif ($name === 'sections') {
            $parameters['sections'] = $words;
        } elseif ($name === 'alpha') {
            $parameters['alpha'] = array_map('intval', $words);
        }
    }
    return ['points' => $points, 'parameters' => $parameters, 'errors' => $errors, 'lines' => count($raw)];
}

function organize($points, $mesh)
{
    $triangles = [];
    $numbers = $directedNumbers = $pairs = [];
    foreach ($mesh->triangles() as $index => $sites) {
        $number = $index + 1;
        $triangles[] = ['number' => $number, 'sites' => $sites];
        $numbers[implode(',', $sites)] = $number;
        [$a, $b, $c] = $sites;
        foreach ([[$a, $b], [$b, $c], [$c, $a]] as [$u, $v]) {
            $directedNumbers[keyOf($u, $v)] = $number;
            $pairs[edgeKey($u, $v)] = [min($u, $v), max($u, $v)];
        }
    }
    $pairs = array_values($pairs);
    usort($pairs, fn($a, $b) => ($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1]));
    $edges = [];
    foreach ($pairs as [$i, $j]) {
        $left = $directedNumbers[keyOf($i, $j)] ?? null;
        $right = $directedNumbers[keyOf($j, $i)] ?? null;
        $edges[] = ['i' => $i, 'j' => $j, 'left' => $left, 'right' => $right,
            'kind' => $left !== null && $right !== null ? 'inner' : 'hull', 'length2' => d2($points[$i], $points[$j])];
    }
    $next = $previous = [];
    foreach ($mesh->hullEdges() as [$u, $v]) {
        $next[$u] = $v;
        $previous[$v] = $u;
    }
    $hull = [];
    $first = min(array_keys($next));
    $current = $first;
    do {
        $hull[] = $current;
        $current = $next[$current];
    } while ($current !== $first);
    $adjacent = array_fill(0, count($points), []);
    foreach ($edges as $edge) {
        $adjacent[$edge['i']][] = $edge['j'];
        $adjacent[$edge['j']][] = $edge['i'];
    }
    $neighbors = [[]];
    for ($site = 1; $site < count($points); $site++) {
        $neighbors[] = neighborOrder($site, $adjacent[$site], $next, $mesh);
    }
    $perimeter = 0.0;
    $area2 = 0;
    foreach ($hull as $i => $site) {
        $a = $points[$site];
        $b = $points[$hull[($i + 1) % count($hull)]];
        $perimeter += sqrt(d2($a, $b));
        $area2 += $a['x'] * $b['y'] - $b['x'] * $a['y'];
    }
    return ['points' => $points, 'mesh' => $mesh, 'triangles' => $triangles, 'numbers' => $numbers,
        'directedNumbers' => $directedNumbers, 'edges' => $edges, 'hull' => $hull, 'next' => $next,
        'previous' => $previous, 'neighbors' => $neighbors, 'perimeter' => $perimeter, 'area2' => $area2];
}

function triangleProperties($model)
{
    $triangles = $model['triangles'];
    $vertices = [];
    foreach ($triangles as &$triangle) {
        $points = array_map(fn($site) => $model['points'][$site], $triangle['sites']);
        $triangle['area2'] = orient(...$points);
        $products = $lengths = $angles = [];
        for ($k = 0; $k < 3; $k++) {
            $products[] = dot($points[$k], $points[($k + 1) % 3], $points[($k + 2) % 3]);
            $lengths[] = d2($points[($k + 1) % 3], $points[($k + 2) % 3]);
            $angles[] = atan2(abs(orient($points[$k], $points[($k + 1) % 3], $points[($k + 2) % 3])), $products[$k]) * 180 / M_PI;
        }
        $triangle['kind'] = in_array(0, $products, true) ? 'right' : (min($products) < 0 ? 'obtuse' : 'acute');
        $shortest = $longest = 0;
        for ($k = 1; $k < 3; $k++) {
            if ($lengths[$k] < $lengths[$shortest]) {
                $shortest = $k;
            }
            if ($lengths[$k] > $lengths[$longest]) {
                $longest = $k;
            }
        }
        $triangle['minimum'] = $angles[$shortest];
        $triangle['maximum'] = $angles[$longest];
        $triangle['radius2'] = radiusSquared($points[0], $points[1], $points[2], $triangle['area2']);
        $vertex = array_merge(['number' => $triangle['number']], circumcenter(...$points), ['radius2' => $triangle['radius2']]);
        $vertex['position'] = vertexPosition($vertex, $model['hull'], $model['points']);
        $vertices[] = $vertex;
    }
    unset($triangle);
    $smallest = $largest = $triangles[0];
    $bins = array_fill(0, 6, 0);
    $total = 0.0;
    foreach ($triangles as $triangle) {
        if ($triangle['minimum'] < $smallest['minimum']) {
            $smallest = $triangle;
        }
        if ($triangle['maximum'] > $largest['maximum']) {
            $largest = $triangle;
        }
        $bins[(int)floor($triangle['minimum'] / 10)]++;
        $total += $triangle['minimum'];
    }
    return ['triangles' => $triangles, 'vertices' => $vertices,
        'quality' => ['smallest' => $smallest, 'largest' => $largest, 'mean' => $total / count($triangles), 'bins' => $bins]];
}

function voronoiCells($model)
{
    $cells = [null];
    $totalArea = $clipTotal = 0.0;
    $largest = null;
    for ($site = 1; $site < count($model['points']); $site++) {
        $bounded = !isset($model['next'][$site]);
        $sequence = [];
        foreach ($model['neighbors'][$site] as $neighbor) {
            $number = $model['directedNumbers'][keyOf($site, $neighbor)] ?? null;
            if ($number !== null) {
                $sequence[] = $number;
            }
        }
        $area = $bounded ? boundedArea($model['points'][$site], $sequence, $model['vertices']) : null;
        $clip = clippedArea($model['points'][$site], $model['neighbors'][$site], $model['points']);
        $cell = ['site' => $site, 'bounded' => $bounded, 'sequence' => $sequence, 'area' => $area, 'clip' => $clip,
            'incoming' => $bounded ? null : outward($site, $model['next'][$site], $model['points']),
            'outgoing' => $bounded ? null : outward($model['previous'][$site], $site, $model['points'])];
        $cells[] = $cell;
        if ($bounded) {
            $totalArea += $area;
            if ($largest === null || $area > $largest['area']) {
                $largest = $cell;
            }
        }
        $clipTotal += $clip;
    }
    return ['cells' => $cells, 'totalArea' => $totalArea, 'clipTotal' => $clipTotal, 'largest' => $largest];
}

function proximityGraphs($model)
{
    $n = count($model['points']) - 1;
    $nearest = nearestNeighbors($model['points'], $model['neighbors']);
    $groups = nearestComponents($nearest);
    $componentOf = array_fill(0, $n + 1, 0);
    $components = [];
    foreach ($groups as $index => $sites) {
        $first = null;
        foreach ($sites as $site) {
            $componentOf[$site] = $index + 1;
            if ($nearest[$nearest[$site]] === $site && $site < $nearest[$site]) {
                $first = $site;
            }
        }
        $components[] = ['number' => $index + 1, 'sites' => $sites, 'pair' => [$first, $nearest[$first]]];
    }
    $mutual = [];
    for ($site = 1; $site <= $n; $site++) {
        if ($site < $nearest[$site] && $nearest[$nearest[$site]] === $site) {
            $mutual[] = [$site, $nearest[$site]];
        }
    }
    $mst = minimumTree($model['edges'], $n);
    $adopted = [];
    $mstLength = 0.0;
    foreach ($mst as $edge) {
        $adopted[edgeKey($edge['i'], $edge['j'])] = true;
        $mstLength += sqrt($edge['length2']);
    }
    $ggDegree = $rngDegree = $mstDegree = array_fill(0, $n + 1, 0);
    $closest = $model['edges'][0];
    $edges = $model['edges'];
    $edgeMap = [];
    foreach ($edges as &$edge) {
        $edge['gabriel'] = gabriel($edge, $model['mesh'], $model['points']);
        $edge['rng'] = relativeNeighborhood($edge, $model['points']);
        $edge['mst'] = isset($adopted[edgeKey($edge['i'], $edge['j'])]);
        if ($edge['length2'] < $closest['length2']) {
            $closest = $edge;
        }
        foreach ([$edge['i'], $edge['j']] as $site) {
            if ($edge['gabriel']) {
                $ggDegree[$site]++;
            }
            if ($edge['rng']) {
                $rngDegree[$site]++;
            }
            if ($edge['mst']) {
                $mstDegree[$site]++;
            }
        }
        $edgeMap[edgeKey($edge['i'], $edge['j'])] = $edge;
    }
    unset($edge);
    return ['nearest' => $nearest, 'components' => $components, 'componentOf' => $componentOf,
        'mutual' => $mutual, 'mst' => $mst, 'mstLength' => $mstLength, 'edges' => $edges,
        'edgeMap' => $edgeMap, 'ggDegree' => $ggDegree, 'rngDegree' => $rngDegree, 'mstDegree' => $mstDegree, 'closest' => $closest];
}

function convexHull($sites, $points)
{
    if (count($sites) <= 2) {
        sort($sites, SORT_NUMERIC);
        return $sites;
    }
    $order = $sites;
    usort($order, fn($a, $b) => ($points[$a]['x'] <=> $points[$b]['x']) ?:
        (($points[$a]['y'] <=> $points[$b]['y']) ?: ($a <=> $b)));
    $chain = function ($values) use ($points) {
        $result = [];
        foreach ($values as $site) {
            while (count($result) >= 2 && orient($points[$result[count($result) - 2]], $points[$result[count($result) - 1]], $points[$site]) <= 0) {
                array_pop($result);
            }
            $result[] = $site;
        }
        return $result;
    };
    $hull = array_merge(array_slice($chain($order), 0, -1), array_slice($chain(array_reverse($order)), 0, -1));
    $start = array_search(min($hull), $hull, true);
    return array_merge(array_slice($hull, $start), array_slice($hull, 0, $start));
}

function convexLayers($points)
{
    $remaining = range(1, count($points) - 1);
    $layers = [];
    $depths = array_fill(0, count($points), 0);
    while ($remaining) {
        $layer = convexHull($remaining, $points);
        $layers[] = $layer;
        foreach ($layer as $site) {
            $depths[$site] = count($layers);
        }
        $removed = array_fill_keys($layer, true);
        $remaining = array_values(array_filter($remaining, fn($site) => !isset($removed[$site])));
    }
    return ['layers' => $layers, 'depths' => $depths];
}

function supportCircle($sites, $points)
{
    if (count($sites) === 1) {
        return ['support' => $sites, 'X' => $points[$sites[0]]['x'], 'Y' => $points[$sites[0]]['y'], 'D' => 1, 'radius2' => 0.0];
    }
    if (count($sites) === 2) {
        [$a, $b] = [$points[$sites[0]], $points[$sites[1]]];
        return ['support' => $sites, 'X' => $a['x'] + $b['x'], 'Y' => $a['y'] + $b['y'], 'D' => 2, 'radius2' => d2($a, $b) / 4];
    }
    [$a, $b, $c] = $sites;
    if (orient($points[$a], $points[$b], $points[$c]) < 0) {
        [$b, $c] = [$c, $b];
    }
    return array_merge(['support' => [$a, $b, $c]], circumcenter($points[$a], $points[$b], $points[$c]),
        ['radius2' => radiusSquared($points[$a], $points[$b], $points[$c], orient($points[$a], $points[$b], $points[$c]))]);
}

function circleMembership($circle, $point, $points)
{
    $support = array_map(fn($site) => $points[$site], $circle['support']);
    if (count($support) === 1) {
        return -d2($point, $support[0]);
    }
    if (count($support) === 2) {
        return -dot($point, $support[0], $support[1]);
    }
    return incircle($support[0], $support[1], $support[2], $point);
}

function enclosingCircle($hull, $points)
{
    $circle = null;
    for ($i = 0; $i < count($hull); $i++) {
        if ($circle !== null && circleMembership($circle, $points[$hull[$i]], $points) >= 0) {
            continue;
        }
        $circle = supportCircle([$hull[$i]], $points);
        for ($j = 0; $j < $i; $j++) {
            if (circleMembership($circle, $points[$hull[$j]], $points) >= 0) {
                continue;
            }
            $circle = supportCircle([$hull[$i], $hull[$j]], $points);
            for ($k = 0; $k < $j; $k++) {
                if (circleMembership($circle, $points[$hull[$k]], $points) < 0) {
                    $circle = supportCircle([$hull[$i], $hull[$j], $hull[$k]], $points);
                }
            }
        }
    }
    $boundary = [];
    for ($site = 1; $site < count($points); $site++) {
        if (circleMembership($circle, $points[$site], $points) === 0) {
            $boundary[] = $site;
        }
    }
    $diameter = null;
    for ($i = 0; $i < count($boundary); $i++) {
        for ($j = $i + 1; $j < count($boundary); $j++) {
            $isDiameter = true;
            foreach ($boundary as $site) {
                if (dot($points[$site], $points[$boundary[$i]], $points[$boundary[$j]]) !== 0) {
                    $isDiameter = false;
                    break;
                }
            }
            if ($isDiameter) {
                $diameter = [$boundary[$i], $boundary[$j]];
            }
        }
    }
    return array_merge(supportCircle($diameter ?? $boundary, $points), ['boundary' => $boundary]);
}

function extent($model)
{
    $candidates = [];
    $empty = null;
    foreach ($model['vertices'] as $vertex) {
        if ($vertex['position'] === 'inside') {
            $candidates[] = $vertex;
            if ($empty === null || $vertex['radius2'] > $empty['radius2']) {
                $empty = $vertex;
            }
        }
    }
    $diameter = null;
    for ($i = 1; $i < count($model['points']); $i++) {
        for ($j = $i + 1; $j < count($model['points']); $j++) {
            $distance = d2($model['points'][$i], $model['points'][$j]);
            if ($diameter === null || $distance > $diameter['length2']) {
                $diameter = ['i' => $i, 'j' => $j, 'length2' => $distance];
            }
        }
    }
    $width = null;
    foreach ($model['hull'] as $t => $u) {
        $v = $model['hull'][($t + 1) % count($model['hull'])];
        $maximum = 0;
        foreach ($model['hull'] as $site) {
            $maximum = max($maximum, orient($model['points'][$u], $model['points'][$v], $model['points'][$site]));
        }
        $value = $maximum / sqrt(d2($model['points'][$u], $model['points'][$v]));
        if ($width === null || $value < $width['value']) {
            $width = ['u' => $u, 'v' => $v, 'value' => $value];
        }
    }
    return ['candidates' => $candidates, 'empty' => $empty, 'diameter' => $diameter, 'width' => $width,
        'enclosing' => enclosingCircle($model['hull'], $model['points'])];
}

function shortestPaths($model)
{
    $paths = [null];
    for ($site = 1; $site < count($model['points']); $site++) {
        $paths[] = dijkstra($site, $model['neighbors'], $model['points']);
    }
    $total = 0.0;
    $pairs = 0;
    $maximum = null;
    for ($i = 1; $i < count($model['points']); $i++) {
        for ($j = $i + 1; $j < count($model['points']); $j++) {
            $distance = sqrt(d2($model['points'][$i], $model['points'][$j]));
            $length = $paths[$i]['distances'][$j];
            $stretch = $length / $distance;
            $total += $stretch;
            $pairs++;
            if ($maximum === null || $stretch > $maximum['stretch']) {
                $maximum = ['i' => $i, 'j' => $j, 'stretch' => $stretch, 'length' => $length, 'distance' => $distance];
            }
        }
    }
    return ['paths' => $paths, 'pairs' => $pairs, 'maximum' => $maximum, 'mean' => $total / $pairs];
}

function alphaComplex($model, $alpha)
{
    $numbers = [];
    $area2 = 0;
    foreach ($model['triangles'] as $triangle) {
        if ($triangle['radius2'] <= $alpha) {
            $numbers[$triangle['number']] = true;
            $area2 += $triangle['area2'];
        }
    }
    $n = count($model['points']) - 1;
    $sets = new DisjointSet($n);
    $touched = [];
    $edges = $boundary = $dangling = 0;
    foreach ($model['edges'] as $edge) {
        $count = ($edge['left'] !== null && isset($numbers[$edge['left']]) ? 1 : 0) +
            ($edge['right'] !== null && isset($numbers[$edge['right']]) ? 1 : 0);
        if ($count === 0 && !($edge['gabriel'] && $edge['length2'] <= 4 * $alpha)) {
            continue;
        }
        $edges++;
        if ($count === 1) {
            $boundary++;
        } elseif ($count === 0) {
            $dangling++;
        }
        $touched[$edge['i']] = $touched[$edge['j']] = true;
        $sets->union($edge['i'], $edge['j']);
    }
    $triangles = count($numbers);
    return ['alpha' => $alpha, 'triangles' => $triangles, 'edges' => $edges, 'boundary' => $boundary,
        'dangling' => $dangling, 'isolated' => $n - count($touched), 'components' => $sets->count,
        'holes' => $sets->count - ($n - $edges + $triangles), 'area2' => $area2];
}

function dualDescription($edge, $model)
{
    if ($edge['kind'] === 'inner') {
        return 'segment ' . $edge['left'] . ' ' . $edge['right'];
    }
    $direction = $edge['left'] !== null ? outward($edge['i'], $edge['j'], $model['points']) : outward($edge['j'], $edge['i'], $model['points']);
    return 'ray ' . ($edge['left'] ?? $edge['right']) . ' ' . joined($direction);
}

function locate($point, $model)
{
    $nearest = 1;
    for ($site = 2; $site < count($model['points']); $site++) {
        if (d2($model['points'][$site], $point) < d2($model['points'][$nearest], $point)) {
            $nearest = $site;
        }
    }
    $place = 'outside';
    $found = false;
    for ($site = 1; $site < count($model['points']); $site++) {
        if ($model['points'][$site]['x'] === $point['x'] && $model['points'][$site]['y'] === $point['y']) {
            $place = 'vertex ' . $site;
            $found = true;
            break;
        }
    }
    if (!$found) {
        foreach ($model['edges'] as $edge) {
            $a = $model['points'][$edge['i']];
            $b = $model['points'][$edge['j']];
            if (orient($a, $b, $point) === 0 && dot($point, $a, $b) < 0) {
                $place = 'edge ' . $edge['i'] . ' ' . $edge['j'];
                $found = true;
                break;
            }
        }
    }
    if (!$found) {
        foreach ($model['triangles'] as $triangle) {
            [$a, $b, $c] = $triangle['sites'];
            if (orient($model['points'][$a], $model['points'][$b], $point) > 0 &&
                orient($model['points'][$b], $model['points'][$c], $point) > 0 &&
                orient($model['points'][$c], $model['points'][$a], $point) > 0) {
                $place = 'triangle ' . joined($triangle['sites']);
                break;
            }
        }
    }
    return $place . ' nearest ' . $nearest . ' d2 ' . d2($model['points'][$nearest], $point);
}

function answerQuery($query, $model)
{
    $kind = $query['kind'];
    $values = $query['values'];
    $i = $values[0];
    $j = $values[1] ?? null;
    if ($kind === 'locate' || $kind === 'walk' || $kind === 'natural') {
        $point = ['x' => $i, 'y' => $j];
        if ($kind === 'locate') {
            return locate($point, $model);
        }
        if ($kind === 'walk') {
            $walk = $model['mesh']->walk($point, $model['triangles'], $model['numbers']);
            $place = $walk['outside'] !== null ? 'outside ' . joined($walk['outside']) : 'triangle ' . $walk['triangle'];
            return 'steps ' . (count($walk['path']) - 1) . ' ' . $place . ' path ' . joined($walk['path']);
        }
        $count = 0;
        $sites = [];
        foreach ($model['triangles'] as $triangle) {
            [$a, $b, $c] = $triangle['sites'];
            if (incircle($model['points'][$a], $model['points'][$b], $model['points'][$c], $point) > 0) {
                $count++;
                foreach ($triangle['sites'] as $site) {
                    $sites[$site] = true;
                }
            }
        }
        $sites = array_keys($sites);
        sort($sites, SORT_NUMERIC);
        return 'triangles ' . $count . ' sites ' . ($sites ? joined($sites) : '-');
    }
    foreach ($values as $site) {
        if ($site < 1 || $site >= count($model['points'])) {
            return 'error unknown_site';
        }
    }
    if ($kind === 'neighbors') {
        return 'degree ' . count($model['neighbors'][$i]) . ' sites ' . joined($model['neighbors'][$i]);
    }
    if ($kind === 'route') {
        $route = greedyRoute($i, $j, $model['neighbors'], $model['points']);
        return 'hops ' . (count($route['path']) - 1) . ' length ' . fixed($route['length']) . ' path ' . joined($route['path']);
    }
    if ($kind === 'path') {
        $sequence = [];
        $current = $j;
        while ($current !== null) {
            $sequence[] = $current;
            if ($current === $i) {
                break;
            }
            $current = $model['paths'][$i]['previous'][$current];
        }
        $sequence = array_reverse($sequence);
        $length = $model['paths'][$i]['distances'][$j];
        $stretch = $i === $j ? '-' : fixed($length / sqrt(d2($model['points'][$i], $model['points'][$j])));
        return 'length ' . fixed($length) . ' stretch ' . $stretch . ' hops ' . (count($sequence) - 1) . ' sites ' . joined($sequence);
    }
    if ($i === $j) {
        return 'error same_site';
    }
    $edge = $model['edgeMap'][edgeKey($i, $j)] ?? null;
    if ($edge !== null) {
        return 'delaunay len2 ' . $edge['length2'] . ' gabriel ' . yesNo($edge['gabriel']) . ' rng ' . yesNo($edge['rng']) .
            ' mst ' . yesNo($edge['mst']) . ' dual ' . dualDescription($edge, $model);
    }
    $crossings = [];
    foreach ($model['edges'] as $edge) {
        $u = $edge['i'];
        $v = $edge['j'];
        if (orient($model['points'][$i], $model['points'][$j], $model['points'][$u]) *
            orient($model['points'][$i], $model['points'][$j], $model['points'][$v]) < 0 &&
            orient($model['points'][$u], $model['points'][$v], $model['points'][$i]) *
            orient($model['points'][$u], $model['points'][$v], $model['points'][$j]) < 0) {
            $crossings[] = $u . '-' . $v;
        }
    }
    return 'missing crossings ' . count($crossings) . ($crossings ? ' ' . joined($crossings) : '');
}

function delaunayPlot($model, $parameters)
{
    $canvas = new Canvas(...$parameters['plot']);
    foreach ($parameters['layers'] as $layer) {
        if ($layer === 'edges') {
            foreach ($model['edges'] as $edge) {
                $canvas->line($model['points'][$edge['i']], $model['points'][$edge['j']], '.');
            }
        } elseif ($layer === 'mst') {
            foreach ($model['mst'] as $edge) {
                $canvas->line($model['points'][$edge['i']], $model['points'][$edge['j']], '*');
            }
        } elseif ($layer === 'hull') {
            foreach ($model['hull'] as $i => $site) {
                $canvas->line($model['points'][$site], $model['points'][$model['hull'][($i + 1) % count($model['hull'])]], '#');
            }
        } elseif ($layer === 'sites') {
            for ($site = 1; $site < count($model['points']); $site++) {
                $canvas->point($model['points'][$site], 'o');
            }
        } elseif ($layer === 'circle' && $model['empty'] !== null) {
            $canvas->point($model['empty'], '@');
        }
    }
    return $canvas->frame();
}

function sections($model, $input)
{
    $n = count($model['points']) - 1;
    $triangleCount = count($model['triangles']);
    $edgeCount = count($model['edges']);
    $hullCount = count($model['hull']);
    $result = [];
    $result['input'] = array_merge(['lines ' . $input['lines'], 'accepted ' . $n, 'rejected ' . count($input['errors'])], $input['errors']);
    $maxFlips = null;
    $flips = $outside = 0;
    foreach ($model['insertions'] as $insertion) {
        $flips += $insertion['flips'];
        if ($insertion['kind'] === 'outside') {
            $outside++;
        }
        if ($maxFlips === null || $insertion['flips'] > $maxFlips['flips']) {
            $maxFlips = $insertion;
        }
    }
    $result['summary'] = ['sites ' . $n, 'triangles ' . $triangleCount, 'edges ' . $edgeCount,
        'hull_vertices ' . $hullCount, 'interior_sites ' . ($n - $hullCount), 'euler ' . ($n - $edgeCount + $triangleCount),
        'flips ' . $flips, 'outside_insertions ' . $outside,
        $maxFlips !== null ? 'max_flips ' . $maxFlips['site'] . ' ' . $maxFlips['flips'] : 'max_flips none'];
    foreach (['acute', 'right', 'obtuse'] as $kind) {
        $count = count(array_filter($model['triangles'], fn($triangle) => $triangle['kind'] === $kind));
        $result['summary'][] = $kind . ' ' . $count;
    }
    $result['insertions'] = ['init ' . joined($model['mesh']->initial)];
    foreach ($model['insertions'] as $insertion) {
        $kind = $insertion['kind'] === 'inside' ? 'inside ' . joined($insertion['containing']) : 'outside ' . $insertion['visible'];
        $result['insertions'][] = 'insert ' . $insertion['site'] . ' ' . $kind . ' flips ' . $insertion['flips'] .
            ' triangles ' . $insertion['triangles'] . ' hull ' . $insertion['hull'];
    }
    $result['triangles'] = [];
    foreach ($model['triangles'] as $triangle) {
        [$a, $b, $c] = $triangle['sites'];
        $adjacent = [];
        foreach ([[$c, $b], [$a, $c], [$b, $a]] as [$u, $v]) {
            $adjacent[] = $model['directedNumbers'][keyOf($u, $v)] ?? '-';
        }
        $result['triangles'][] = 'tri ' . $triangle['number'] . ' ' . joined($triangle['sites']) . ' area2 ' . $triangle['area2'] .
            ' ' . $triangle['kind'] . ' adj ' . joined($adjacent);
    }
    $result['edges'] = [];
    foreach ($model['edges'] as $edge) {
        $result['edges'][] = 'edge ' . $edge['i'] . ' ' . $edge['j'] . ' ' . $edge['kind'] . ' len2 ' . $edge['length2'] .
            ' left ' . ($edge['left'] ?? '-') . ' right ' . ($edge['right'] ?? '-');
    }
    $result['hull'] = ['hull_vertices ' . $hullCount, 'order ' . joined($model['hull']),
        'perimeter ' . fixed($model['perimeter']), 'area2 ' . $model['area2']];
    $result['convex_layers'] = ['layers ' . count($model['layers'])];
    foreach ($model['layers'] as $i => $layer) {
        $result['convex_layers'][] = 'layer ' . ($i + 1) . ' size ' . count($layer) . ' sites ' . joined($layer);
    }
    $result['quality'] = ['min_angle ' . fixed($model['quality']['smallest']['minimum']) . ' tri ' . $model['quality']['smallest']['number'],
        'max_angle ' . fixed($model['quality']['largest']['maximum']) . ' tri ' . $model['quality']['largest']['number'],
        'mean_min_angle ' . fixed($model['quality']['mean'])];
    foreach ($model['quality']['bins'] as $i => $count) {
        $result['quality'][] = 'bin ' . ($i * 10) . ' ' . (($i + 1) * 10) . ' ' . $count;
    }
    $result['vertices'] = [];
    foreach (['inside', 'on', 'outside'] as $location) {
        $result['vertices'][] = $location . ' ' . count(array_filter($model['vertices'], fn($vertex) => $vertex['position'] === $location));
    }
    foreach ($model['vertices'] as $vertex) {
        $result['vertices'][] = 'v ' . $vertex['number'] . ' ' . fraction($vertex['X'], $vertex['D']) . ' ' . fraction($vertex['Y'], $vertex['D']) .
            ' r ' . fixed(sqrt($vertex['radius2'])) . ' ' . $vertex['position'];
    }
    $innerCount = count(array_filter($model['edges'], fn($edge) => $edge['kind'] === 'inner'));
    $result['voronoi_edges'] = ['segments ' . $innerCount, 'rays ' . $hullCount];
    foreach ($model['edges'] as $edge) {
        $result['voronoi_edges'][] = 've ' . $edge['i'] . ' ' . $edge['j'] . ' ' . dualDescription($edge, $model);
    }
    $result['cells'] = ['bounded ' . ($n - $hullCount), 'unbounded ' . $hullCount,
        'total_area ' . fixed($model['totalArea']), 'clip_total ' . fixed($model['clipTotal']),
        $model['largest'] !== null ? 'largest ' . $model['largest']['site'] . ' area ' . fixed($model['largest']['area']) : 'largest none'];
    for ($site = 1; $site <= $n; $site++) {
        $cell = $model['cells'][$site];
        if ($cell['bounded']) {
            $result['cells'][] = 'cell ' . $site . ' bounded ' . count($cell['sequence']) . ' area ' . fixed($cell['area']) .
                ' clip ' . fixed($cell['clip']) . ' vertices ' . joined($cell['sequence']);
        } else {
            $result['cells'][] = 'cell ' . $site . ' unbounded ' . count($cell['sequence']) . ' clip ' . fixed($cell['clip']) .
                ' from ' . joined($cell['incoming']) . ' vertices ' . joined($cell['sequence']) . ' to ' . joined($cell['outgoing']);
        }
    }
    $closest = $model['closest'];
    $result['nearest'] = ['mutual_pairs ' . count($model['mutual']), 'closest_pair ' . $closest['i'] . ' ' . $closest['j'] . ' d2 ' . $closest['length2']];
    for ($site = 1; $site <= $n; $site++) {
        $nearest = $model['nearest'][$site];
        $result['nearest'][] = 'nn ' . $site . ' ' . $nearest . ' d2 ' . d2($model['points'][$site], $model['points'][$nearest]) .
            ' ' . ($model['nearest'][$nearest] === $site ? 'mutual' : '-');
    }
    $result['components'] = ['components ' . count($model['components'])];
    foreach ($model['components'] as $component) {
        $result['components'][] = 'component ' . $component['number'] . ' size ' . count($component['sites']) .
            ' pair ' . joined($component['pair']) . ' sites ' . joined($component['sites']);
    }
    $longest = $model['mst'][count($model['mst']) - 1];
    $result['mst'] = ['edges ' . ($n - 1), 'total_length ' . fixed($model['mstLength']),
        'longest ' . $longest['i'] . ' ' . $longest['j'] . ' len2 ' . $longest['length2']];
    foreach ($model['mst'] as $edge) {
        $result['mst'][] = 'mst ' . $edge['i'] . ' ' . $edge['j'] . ' len2 ' . $edge['length2'];
    }
    $gabrielCount = count(array_filter($model['edges'], fn($edge) => $edge['gabriel']));
    $rngCount = count(array_filter($model['edges'], fn($edge) => $edge['rng']));
    $result['proximity'] = ['delaunay ' . $edgeCount, 'gabriel ' . $gabrielCount, 'rng ' . $rngCount,
        'mst ' . ($n - 1), 'nn ' . ($n - count($model['mutual']))];
    foreach ($model['edges'] as $edge) {
        if ($edge['rng'] && !$edge['mst']) {
            $result['proximity'][] = 'rng_extra ' . $edge['i'] . ' ' . $edge['j'] . ' len2 ' . $edge['length2'];
        }
    }
    $degrees = array_map('count', array_slice($model['neighbors'], 1));
    $counts = array_count_values($degrees);
    ksort($counts, SORT_NUMERIC);
    $result['degrees'] = ['min ' . min($degrees), 'max ' . max($degrees)];
    foreach ($counts as $degree => $count) {
        $result['degrees'][] = 'degree ' . $degree . ' count ' . $count;
    }
    $result['empty_circle'] = ['candidates ' . count($model['candidates'])];
    if ($model['empty'] === null) {
        $result['empty_circle'][] = 'none';
    } else {
        $empty = $model['empty'];
        $result['empty_circle'][] = 'vertex ' . $empty['number'];
        $result['empty_circle'][] = 'center ' . fraction($empty['X'], $empty['D']) . ' ' . fraction($empty['Y'], $empty['D']);
        $result['empty_circle'][] = 'radius ' . fixed(sqrt($empty['radius2']));
        $result['empty_circle'][] = 'sites ' . joined($model['triangles'][$empty['number'] - 1]['sites']);
    }
    $diameter = $model['diameter'];
    $width = $model['width'];
    $enclosing = $model['enclosing'];
    $result['extent'] = ['diameter ' . $diameter['i'] . ' ' . $diameter['j'] . ' d2 ' . $diameter['length2'],
        'width ' . fixed($width['value']) . ' edge ' . $width['u'] . ' ' . $width['v'],
        'enclosing_center ' . fraction($enclosing['X'], $enclosing['D']) . ' ' . fraction($enclosing['Y'], $enclosing['D']),
        'enclosing_radius ' . fixed(sqrt($enclosing['radius2'])), 'enclosing_sites ' . joined($enclosing['boundary'])];
    $maximum = $model['maximum'];
    $result['spanner'] = ['pairs ' . $model['pairs'], 'max_stretch ' . fixed($maximum['stretch']) . ' pair ' . $maximum['i'] . ' ' . $maximum['j'] .
        ' length ' . fixed($maximum['length']) . ' distance ' . fixed($maximum['distance']), 'mean_stretch ' . fixed($model['mean'])];
    $result['alpha'] = [];
    foreach ($input['parameters']['alpha'] as $value) {
        $alpha = alphaComplex($model, $value);
        $result['alpha'][] = 'alpha ' . $alpha['alpha'] . ' triangles ' . $alpha['triangles'] . ' edges ' . $alpha['edges'] .
            ' boundary ' . $alpha['boundary'] . ' dangling ' . $alpha['dangling'] . ' isolated ' . $alpha['isolated'] .
            ' components ' . $alpha['components'] . ' holes ' . $alpha['holes'] . ' area2 ' . $alpha['area2'];
    }
    $result['sites'] = [];
    for ($site = 1; $site <= $n; $site++) {
        $point = $model['points'][$site];
        $result['sites'][] = 'site ' . $site . ' ' . $point['x'] . ' ' . $point['y'] . ' ' . (isset($model['next'][$site]) ? 'hull' : 'inner') .
            ' dt ' . count($model['neighbors'][$site]) . ' gg ' . $model['ggDegree'][$site] . ' rng ' . $model['rngDegree'][$site] .
            ' mst ' . $model['mstDegree'][$site] . ' nn ' . $model['nearest'][$site] . ' comp ' . $model['componentOf'][$site] .
            ' depth ' . $model['depths'][$site];
    }
    $result['queries'] = [];
    foreach ($input['parameters']['queries'] as $query) {
        $result['queries'][] = $query['text'] . ' ' . answerQuery($query, $model);
    }
    $result['delaunay_plot'] = delaunayPlot($model, $input['parameters']);
    $result['voronoi_plot'] = voronoiPlot($input['parameters']['plot'][0], $input['parameters']['plot'][1], $model['points']);
    return $result;
}

function main()
{
    $input = readInput();
    $mesh = new Triangulation($input['points']);
    $insertions = [];
    for ($site = 4; $site < count($input['points']); $site++) {
        $insertions[] = $mesh->insert($site);
    }
    $model = array_merge(organize($input['points'], $mesh), ['insertions' => $insertions]);
    $model = array_merge($model, triangleProperties($model));
    $model = array_merge($model, voronoiCells($model));
    $model = array_merge($model, proximityGraphs($model));
    $model = array_merge($model, convexLayers($model['points']));
    $model = array_merge($model, extent($model));
    $model = array_merge($model, shortestPaths($model));
    $contents = sections($model, $input);
    $groups = [
        'triangulation.txt' => ['input', 'summary', 'insertions', 'triangles', 'edges', 'hull', 'convex_layers', 'quality'],
        'voronoi.txt' => ['vertices', 'voronoi_edges', 'cells'],
        'derived.txt' => ['nearest', 'components', 'mst', 'proximity', 'degrees', 'empty_circle', 'extent', 'spanner', 'alpha', 'sites', 'queries'],
        'plot.txt' => ['delaunay_plot', 'voronoi_plot']
    ];
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    foreach ($groups as $file => $names) {
        $lines = [];
        foreach ($input['parameters']['sections'] as $name) {
            if (in_array($name, $names, true)) {
                $lines[] = '[' . $name . ']';
                array_push($lines, ...$contents[$name]);
            }
        }
        file_put_contents('output/' . $file, $lines ? implode("\n", $lines) . "\n" : '');
    }
}

main();
