<?php

require_once __DIR__ . '/pgm_io.php';
require_once __DIR__ . '/filters.php';
require_once __DIR__ . '/canny.php';
require_once __DIR__ . '/hough.php';
require_once __DIR__ . '/corners.php';

function floorDiv(int $numerator, int $denominator): int
{
    $quotient = intdiv($numerator, $denominator);
    return $numerator < 0 && $numerator % $denominator !== 0 ? $quotient - 1 : $quotient;
}

function rounded(int $numerator, int $denominator): int
{
    if ($denominator < 0) {
        $numerator = -$numerator;
        $denominator = -$denominator;
    }
    return floorDiv(2 * $numerator + $denominator, 2 * $denominator);
}

function pointCross(array $a, array $b): int
{
    return $a['x'] * $b['y'] - $a['y'] * $b['x'];
}

function subtract(array $a, array $b): array
{
    return ['x' => $a['x'] - $b['x'], 'y' => $a['y'] - $b['y']];
}

function distance(array $a, array $b): int
{
    return max(abs($a['x'] - $b['x']), abs($a['y'] - $b['y']));
}

function angleDifference(int $a, int $b): int
{
    $difference = abs($a - $b);
    return min($difference, 180 - $difference);
}

function insideImage(array $point, int $width, int $height): bool
{
    return $point['x'] >= 0 && $point['x'] < $width && $point['y'] >= 0 && $point['y'] < $height;
}

function bresenham(array $start, array $end): array
{
    $dx = abs($end['x'] - $start['x']);
    $dy = -abs($end['y'] - $start['y']);
    $sx = $start['x'] < $end['x'] ? 1 : -1;
    $sy = $start['y'] < $end['y'] ? 1 : -1;
    $x = $start['x'];
    $y = $start['y'];
    $error = $dx + $dy;
    $points = [];
    while (true) {
        $points[] = ['x' => $x, 'y' => $y];
        if ($x === $end['x'] && $y === $end['y']) return $points;
        $twice = 2 * $error;
        if ($twice >= $dy) {
            $error += $dy;
            $x += $sx;
        }
        if ($twice <= $dx) {
            $error += $dx;
            $y += $sy;
        }
    }
}

function circumference(array $circle, array $point): bool
{
    $dx = $point['x'] - $circle['x'];
    $dy = $point['y'] - $circle['y'];
    $squared = $dx * $dx + $dy * $dy;
    return ($circle['radius'] - 1) * ($circle['radius'] - 1) <= $squared &&
        $squared <= ($circle['radius'] + 1) * ($circle['radius'] + 1);
}

function circleGaps(array $circle, array $edges, int $width, int $height): array
{
    $offsets = $circle['offsets'];
    $half = fn($p) => $p['y'] > 0 || ($p['y'] === 0 && $p['x'] > 0) ? 0 : 1;
    usort($offsets, fn($a, $b) => ($half($a) <=> $half($b)) ?: (-pointCross($a, $b)));
    $hits = [];
    foreach ($offsets as $offset) {
        $point = ['x' => $circle['x'] + $offset['x'], 'y' => $circle['y'] + $offset['y']];
        $hits[] = insideImage($point, $width, $height) && $edges[$point['y'] * $width + $point['x']] ? 1 : 0;
    }
    $total = array_sum($hits);
    $n = count($hits);
    if ($total === 0) return ['gap' => $n, 'arcs' => 0];
    if ($total === $n) return ['gap' => 0, 'arcs' => 1];
    $arcs = $gap = $run = 0;
    for ($i = 0; $i < $n; $i++) if ($hits[$i] && !$hits[($i + $n - 1) % $n]) $arcs++;
    $first = array_search(1, $hits, true);
    for ($step = 1; $step <= $n; $step++) {
        if ($hits[($first + $step) % $n]) $run = 0;
        else {
            $run++;
            $gap = max($gap, $run);
        }
    }
    return compact('gap', 'arcs');
}

function selectCircles(array $peaks, array $edges, int $width, int $height, int $maximum): array
{
    usort($peaks, fn($a, $b) => (($b['votes'] * $a['points']) <=> ($a['votes'] * $b['points'])) ?:
        ($a['radius'] <=> $b['radius']) ?: ($a['y'] <=> $b['y']) ?: ($a['x'] <=> $b['x']));
    $circles = [];
    foreach (array_slice($peaks, 0, $maximum) as $peak) {
        $circles[] = $peak + ['type' => 'circle', 'number' => count($circles) + 1] + circleGaps($peak, $edges, $width, $height) + ['explained' => []];
    }
    return $circles;
}

function removeCirclePixels(array $edges, array &$circles, int $width): array
{
    $pixels = [];
    $removed = array_fill(0, count($edges), 0);
    foreach ($edges as $index => $edge) {
        if (!$edge) continue;
        $point = ['x' => $index % $width, 'y' => intdiv($index, $width), 'index' => $index];
        foreach ($circles as &$circle) {
            if (circumference($circle, $point)) {
                $removed[$index] = 1;
                $circle['explained'][$index] = true;
            }
        }
        unset($circle);
        if (!$removed[$index]) $pixels[] = $point;
    }
    return compact('pixels', 'removed');
}

function extractSegments(array $peaks, array $pixels, array $trig, array $params, int $size): array
{
    usort($peaks, fn($a, $b) => ($b['votes'] <=> $a['votes']) ?: ($a['theta'] <=> $b['theta']) ?: ($a['rho'] <=> $b['rho']));
    $used = array_fill(0, $size, 0);
    $lines = $segments = [];
    foreach ($peaks as $peak) {
        if (count($lines) === $params['hough_max_lines']) break;
        $selected = [];
        foreach ($pixels as $point) {
            if (!$used[$point['index']] && abs(rho($point, $peak['theta'], $trig, $params['hough_rho_step']) - $peak['rho']) <= $params['segment_tolerance']) {
                $point['u'] = $point['y'] * $trig['cos'][$peak['theta']] - $point['x'] * $trig['sin'][$peak['theta']];
                $selected[] = $point;
            }
        }
        usort($selected, fn($a, $b) => ($a['u'] <=> $b['u']) ?: ($a['x'] <=> $b['x']) ?: ($a['y'] <=> $b['y']));
        $groups = [];
        foreach ($selected as $i => $point) {
            if ($i === 0 || $point['u'] - $selected[$i - 1]['u'] > $params['segment_max_gap'] * 16384) $groups[] = [];
            $groups[count($groups) - 1][] = $point;
        }
        $accepted = [];
        foreach ($groups as $group) {
            if (distance($group[0], $group[count($group) - 1]) + 1 >= $params['segment_min_length']) $accepted[] = $group;
        }
        if (!$accepted) continue;
        $line = $peak + ['number' => count($lines) + 1, 'segments' => []];
        foreach ($accepted as $group) {
            $start = $group[0];
            $end = $group[count($group) - 1];
            $indices = array_map(fn($p) => $p['index'], $group);
            $segment = ['number' => count($segments) + 1, 'line' => $line['number'], 'theta' => $peak['theta'],
                'start' => $start, 'end' => $end, 'length' => distance($start, $end) + 1, 'pixels' => $indices];
            foreach ($indices as $index) $used[$index] = 1;
            $segments[] = $segment;
            $line['segments'][] = $segment;
        }
        $lines[] = $line;
    }
    return compact('lines', 'segments', 'used');
}

function findJunctions(array $segments, array $params): array
{
    $adjacency = array_fill(0, count($segments), []);
    $count = 0;
    for ($a = 0; $a < count($segments); $a++) {
        for ($b = $a + 1; $b < count($segments); $b++) {
            $first = $segments[$a];
            $second = $segments[$b];
            if (angleDifference($first['theta'], $second['theta']) < $params['junction_min_angle']) continue;
            $da = subtract($first['end'], $first['start']);
            $db = subtract($second['end'], $second['start']);
            $denominator = pointCross($da, $db);
            if ($denominator === 0) continue;
            $lambda = pointCross(subtract($second['start'], $first['start']), $db);
            $point = ['x' => rounded($first['start']['x'] * $denominator + $lambda * $da['x'], $denominator),
                'y' => rounded($first['start']['y'] * $denominator + $lambda * $da['y'], $denominator)];
            $endA = distance($first['start'], $point) <= distance($first['end'], $point) ? 0 : 1;
            $endB = distance($second['start'], $point) <= distance($second['end'], $point) ? 0 : 1;
            if (distance($endA ? $first['end'] : $first['start'], $point) > $params['junction_distance'] ||
                distance($endB ? $second['end'] : $second['start'], $point) > $params['junction_distance']) continue;
            $adjacency[$a][$b] = ['point' => $point, 'end' => $endA];
            $adjacency[$b][$a] = ['point' => $point, 'end' => $endB];
            $count++;
        }
    }
    return compact('adjacency', 'count');
}

function findPolygons(array $segments, array $adjacency): array
{
    $polygons = [];
    $neighbors = [];
    foreach ($adjacency as $map) {
        $indices = array_keys($map);
        sort($indices, SORT_NUMERIC);
        $neighbors[] = $indices;
    }
    foreach ([3, 4] as $size) {
        for ($first = 0; $first < count($segments); $first++) {
            $path = [$first];
            $visit = function () use (&$visit, &$path, &$polygons, $size, $first, $neighbors, $adjacency, $segments): void {
                $last = $path[count($path) - 1];
                if (count($path) === $size) {
                    if ($path[1] >= $last || !isset($adjacency[$last][$first])) return;
                    if ($adjacency[$last][$path[$size - 2]]['end'] === $adjacency[$last][$first]['end'] ||
                        $adjacency[$first][$last]['end'] === $adjacency[$first][$path[1]]['end']) return;
                    $vertices = [];
                    foreach ($path as $i => $current) $vertices[] = $adjacency[$current][$path[($i + $size - 1) % $size]]['point'];
                    $positive = $negative = true;
                    for ($i = 0; $i < $size; $i++) {
                        $turn = pointCross(subtract($vertices[($i + 1) % $size], $vertices[$i]),
                            subtract($vertices[($i + 2) % $size], $vertices[($i + 1) % $size]));
                        if ($turn <= 0) $positive = false;
                        if ($turn >= 0) $negative = false;
                    }
                    if (!$positive && !$negative) return;
                    $polygons[] = ['type' => 'polygon', 'segments' => array_map(fn($i) => $segments[$i], $path), 'vertices' => $vertices];
                    return;
                }
                foreach ($neighbors[$last] as $next) {
                    if ($next <= $first || in_array($next, $path, true)) continue;
                    if (count($path) > 1 && $adjacency[$last][$path[count($path) - 2]]['end'] === $adjacency[$last][$next]['end']) continue;
                    $path[] = $next;
                    $visit();
                    array_pop($path);
                }
            };
            $visit();
        }
    }
    usort($polygons, function ($a, $b) {
        $order = count($a['segments']) <=> count($b['segments']);
        if ($order !== 0) return $order;
        foreach ($a['segments'] as $i => $segment) {
            $order = $segment['number'] <=> $b['segments'][$i]['number'];
            if ($order !== 0) return $order;
        }
        return 0;
    });
    foreach ($polygons as $i => &$polygon) $polygon['number'] = $i + 1;
    unset($polygon);
    return $polygons;
}

function polygonAttributes(array &$polygon, array $edges, int $width, int $height, array $params): void
{
    $vertices = $polygon['vertices'];
    $size = count($vertices);
    $polygon['angles'] = $polygon['length2'] = $polygon['support'] = [];
    $polygon['sigma'] = 0;
    $polygon['explained'] = [];
    for ($i = 0; $i < $size; $i++) {
        $before = $vertices[($i + $size - 1) % $size];
        $here = $vertices[$i];
        $next = $vertices[($i + 1) % $size];
        $left = subtract($before, $here);
        $right = subtract($next, $here);
        $phi = angleDifference($polygon['segments'][($i + $size - 1) % $size]['theta'], $polygon['segments'][$i]['theta']);
        $polygon['angles'][] = $left['x'] * $right['x'] + $left['y'] * $right['y'] < 0 ? 180 - $phi : $phi;
        $polygon['length2'][] = $right['x'] * $right['x'] + $right['y'] * $right['y'];
        $polygon['sigma'] += pointCross($here, $next);
        $points = bresenham($here, $next);
        $supported = 0;
        foreach ($points as $point) {
            $hit = false;
            for ($dy = -1; $dy <= 1; $dy++) {
                for ($dx = -1; $dx <= 1; $dx++) {
                    $p = ['x' => $point['x'] + $dx, 'y' => $point['y'] + $dy];
                    if (!insideImage($p, $width, $height)) continue;
                    $index = $p['y'] * $width + $p['x'];
                    if ($edges[$index]) {
                        $polygon['explained'][$index] = true;
                        $hit = true;
                    }
                }
            }
            if ($hit) $supported++;
        }
        $polygon['support'][] = intdiv(100 * $supported, count($points));
    }
    $absolute = abs($polygon['sigma']);
    $polygon['area'] = intdiv($absolute, 2) . '.' . ($absolute % 2 ? '5' : '0');
    $tolerance = $params['angle_tolerance'];
    if ($size === 3) {
        $equilateral = true;
        $right = false;
        foreach ($polygon['angles'] as $angle) {
            if (abs($angle - 60) > $tolerance) $equilateral = false;
            if (abs($angle - 90) <= $tolerance) $right = true;
        }
        $polygon['kind'] = $equilateral ? 'equilateral_triangle' : ($right ? 'right_triangle' : 'triangle');
        return;
    }
    $parallelA = angleDifference($polygon['segments'][0]['theta'], $polygon['segments'][2]['theta']) <= $tolerance;
    $parallelB = angleDifference($polygon['segments'][1]['theta'], $polygon['segments'][3]['theta']) <= $tolerance;
    if (!$parallelA && !$parallelB) $polygon['kind'] = 'quadrilateral';
    elseif ($parallelA !== $parallelB) $polygon['kind'] = 'trapezoid';
    else {
        $right = true;
        foreach ($polygon['angles'] as $angle) if (abs($angle - 90) > $tolerance) $right = false;
        if (!$right) $polygon['kind'] = 'parallelogram';
        else {
            $maximum = max($polygon['length2']);
            $minimum = min($polygon['length2']);
            $polygon['kind'] = 100 * ($maximum - $minimum) <= $params['square_tolerance'] * $maximum ? 'square' : 'rectangle';
        }
    }
}

function representatives(array $shape): array
{
    if ($shape['type'] === 'polygon') return $shape['vertices'];
    $x = $shape['x'];
    $y = $shape['y'];
    $r = $shape['radius'];
    return [['x' => $x + $r, 'y' => $y], ['x' => $x, 'y' => $y + $r],
        ['x' => $x - $r, 'y' => $y], ['x' => $x, 'y' => $y - $r]];
}

function shapeContains(array $shape, array $point): bool
{
    if ($shape['type'] === 'circle') {
        $dx = $point['x'] - $shape['x'];
        $dy = $point['y'] - $shape['y'];
        return $dx * $dx + $dy * $dy <= $shape['radius'] * $shape['radius'];
    }
    foreach ($shape['vertices'] as $i => $vertex) {
        $next = $shape['vertices'][($i + 1) % count($shape['vertices'])];
        $cross = pointCross(subtract($next, $vertex), subtract($point, $vertex));
        if ($cross !== 0 && ($cross > 0) !== ($shape['sigma'] > 0)) return false;
    }
    return true;
}

function measureShapes(array &$shapes, array $image, int $margin): void
{
    foreach ($shapes as &$shape) {
        $points = representatives($shape);
        $xs = array_column($points, 'x');
        $ys = array_column($points, 'y');
        $x0 = max(0, min($xs) - $margin);
        $x1 = min($image['width'] - 1, max($xs) + $margin);
        $y0 = max(0, min($ys) - $margin);
        $y1 = min($image['height'] - 1, max($ys) + $margin);
        $inner = $innerSum = $outer = $outerSum = 0;
        for ($y = $y0; $y <= $y1; $y++) {
            for ($x = $x0; $x <= $x1; $x++) {
                if (shapeContains($shape, ['x' => $x, 'y' => $y])) {
                    $inner++;
                    $innerSum += $image['pixels'][$y * $image['width'] + $x];
                } else {
                    $outer++;
                    $outerSum += $image['pixels'][$y * $image['width'] + $x];
                }
            }
        }
        $shape['pixelCount'] = $inner;
        $shape['mean'] = $inner ? intdiv($innerSum, $inner) : 0;
        $shape['contrast'] = $shape['mean'] - ($outer ? intdiv($outerSum, $outer) : 0);
    }
    unset($shape);
    foreach ($shapes as $index => $shape) {
        $best = null;
        foreach ($shapes as $otherIndex => $other) {
            if ($otherIndex === $index || $other['pixelCount'] <= $shape['pixelCount'] ||
                ($best !== null && $other['pixelCount'] >= $shapes[$best]['pixelCount'])) continue;
            $contains = true;
            foreach (representatives($shape) as $point) if (!shapeContains($other, $point)) $contains = false;
            if ($contains) $best = $otherIndex;
        }
        $shapes[$index]['enclosing'] = $best === null ? 'none' : $shapes[$best]['type'] . ' ' . $shapes[$best]['number'];
    }
}

function matchCorners(array &$corners, array &$polygons, array $segments, int $maximum): void
{
    foreach ($corners as &$corner) {
        $corner['match'] = $corner['matchKind'] = 'none';
        $best = $maximum + 1;
        foreach ($polygons as $polygon) {
            foreach ($polygon['vertices'] as $i => $vertex) {
                $delta = distance($corner, $vertex);
                if ($delta <= $maximum && $delta < $best) {
                    $best = $delta;
                    $corner['match'] = 'polygon ' . $polygon['number'] . ' vertex ' . ($i + 1);
                    $corner['matchKind'] = 'polygon';
                }
            }
        }
        if ($corner['matchKind'] === 'polygon') continue;
        foreach ($segments as $segment) {
            foreach (['start', 'end'] as $end) {
                $delta = distance($corner, $segment[$end]);
                if ($delta <= $maximum && $delta < $best) {
                    $best = $delta;
                    $corner['match'] = 'segment ' . $segment['number'] . ' ' . $end;
                    $corner['matchKind'] = 'segment';
                }
            }
        }
    }
    unset($corner);
    foreach ($polygons as &$polygon) {
        $polygon['vertexCorners'] = [];
        foreach ($polygon['vertices'] as $vertex) {
            $best = $maximum + 1;
            $selected = null;
            foreach ($corners as $corner) {
                $delta = distance($vertex, $corner);
                if ($delta <= $maximum && $delta < $best) {
                    $best = $delta;
                    $selected = $corner['number'];
                }
            }
            $polygon['vertexCorners'][] = $selected;
        }
    }
    unset($polygon);
}

function describeComponents(array $groups, array $edges, array $magnitude, array $direction, array $shapes, int $width, int $height): array
{
    $result = [];
    foreach ($groups as $i => $pixels) {
        $minX = $width;
        $minY = $height;
        $maxX = $maxY = -1;
        $ends = $sum = 0;
        $directions = [0 => 0, 45 => 0, 90 => 0, 135 => 0];
        foreach ($pixels as $index) {
            $x = $index % $width;
            $y = intdiv($index, $width);
            $minX = min($minX, $x);
            $maxX = max($maxX, $x);
            $minY = min($minY, $y);
            $maxY = max($maxY, $y);
            $sum += $magnitude[$index];
            $directions[$direction[$index]]++;
            $adjacent = 0;
            foreach (neighbors($index, $width, $height) as $next) if ($edges[$next]) $adjacent++;
            if ($adjacent === 1) $ends++;
        }
        $mainDirection = 0;
        foreach ([45, 90, 135] as $d) if ($directions[$d] > $directions[$mainDirection]) $mainDirection = $d;
        $matching = 'none';
        $explained = 0;
        foreach ($shapes as $shape) {
            $matched = 0;
            foreach ($pixels as $index) if (isset($shape['explained'][$index])) $matched++;
            if ($matched > $explained) {
                $matching = $shape['type'] . ' ' . $shape['number'];
                $explained = $matched;
            }
        }
        $result[] = ['number' => $i + 1, 'pixels' => count($pixels), 'box' => [$minX, $minY, $maxX, $maxY],
            'ends' => $ends, 'strength' => intdiv($sum, count($pixels)), 'direction' => $mainDirection,
            'matching' => $matching, 'explained' => $explained];
    }
    return $result;
}

function voteImage(array $votes, int $width, int $height, array $trig, int $step): array
{
    $points = [['x' => 0, 'y' => 0], ['x' => $width - 1, 'y' => 0],
        ['x' => 0, 'y' => $height - 1], ['x' => $width - 1, 'y' => $height - 1]];
    $low = $high = 0;
    $maximum = 0;
    for ($theta = 0; $theta < 180; $theta++) {
        foreach ($points as $point) {
            $r = rho($point, $theta, $trig, $step);
            $low = min($low, $r);
            $high = max($high, $r);
        }
        foreach ($votes[$theta] as $value) $maximum = max($maximum, $value);
    }
    $pixels = array_fill(0, 180 * ($high - $low + 1), 0);
    if ($maximum > 0) {
        for ($r = $low; $r <= $high; $r++) {
            for ($theta = 0; $theta < 180; $theta++) {
                $pixels[($r - $low) * 180 + $theta] = intdiv(255 * ($votes[$theta][$r] ?? 0), $maximum);
            }
        }
    }
    return ['pixels' => $pixels, 'height' => $high - $low + 1, 'maximum' => $maximum];
}

function overlayImage(array $image, array $segments, array $circles, array $corners, int $divisor): array
{
    $width = $image['width'];
    $height = $image['height'];
    $pixels = array_map(fn($value) => intdiv($value, $divisor), $image['pixels']);
    $mark = function (array $point) use (&$pixels, $width, $height): void {
        if (insideImage($point, $width, $height)) $pixels[$point['y'] * $width + $point['x']] = 255;
    };
    foreach ($segments as $segment) foreach (bresenham($segment['start'], $segment['end']) as $point) $mark($point);
    foreach ($circles as $circle) {
        foreach ($circle['offsets'] as $offset) $mark(['x' => $circle['x'] + $offset['x'], 'y' => $circle['y'] + $offset['y']]);
    }
    foreach ($corners as $corner) {
        for ($e = -2; $e <= 2; $e++) {
            $mark(['x' => $corner['x'] + $e, 'y' => $corner['y']]);
            $mark(['x' => $corner['x'], 'y' => $corner['y'] + $e]);
        }
    }
    return $pixels;
}

function writeText(string $name, array $lines): void
{
    file_put_contents('output/' . $name . '.txt', implode("\n", $lines) . "\n");
}

function writeLists(array $lines, array $circles, array $polygons, array $corners, array $components): void
{
    $text = ['lines ' . count($lines)];
    foreach ($lines as $line) {
        $text[] = 'line ' . $line['number'] . ' theta ' . $line['theta'] . ' rho ' . $line['rho'] .
            ' votes ' . $line['votes'] . ' segments ' . count($line['segments']);
        foreach ($line['segments'] as $segment) {
            $text[] = 'segment ' . $segment['number'] . ' start ' . $segment['start']['x'] . ' ' . $segment['start']['y'] .
                ' end ' . $segment['end']['x'] . ' ' . $segment['end']['y'] . ' length ' . $segment['length'] . ' pixels ' . count($segment['pixels']);
        }
    }
    writeText('lines', $text);
    $text = ['circles ' . count($circles)];
    foreach ($circles as $circle) {
        $text[] = 'circle ' . $circle['number'] . ' center ' . $circle['x'] . ' ' . $circle['y'] . ' radius ' . $circle['radius'] .
            ' votes ' . $circle['votes'] . ' points ' . $circle['points'] . ' gap ' . $circle['gap'] . ' arcs ' . $circle['arcs'] .
            ' pixels ' . $circle['pixelCount'] . ' mean ' . $circle['mean'] . ' contrast ' . $circle['contrast'] . ' inside ' . $circle['enclosing'];
    }
    writeText('circles', $text);
    $text = ['polygons ' . count($polygons)];
    foreach ($polygons as $polygon) {
        $numbers = array_map(fn($segment) => $segment['number'], $polygon['segments']);
        $text[] = 'polygon ' . $polygon['number'] . ' ' . $polygon['kind'] . ' segments ' . implode(' ', $numbers) . ' area ' . $polygon['area'] .
            ' pixels ' . $polygon['pixelCount'] . ' mean ' . $polygon['mean'] . ' contrast ' . $polygon['contrast'] . ' inside ' . $polygon['enclosing'];
        foreach ($polygon['vertices'] as $i => $vertex) {
            $text[] = 'vertex ' . ($i + 1) . ' ' . $vertex['x'] . ' ' . $vertex['y'] . ' angle ' . $polygon['angles'][$i] .
                ' corner ' . ($polygon['vertexCorners'][$i] ?? 'none');
        }
        foreach ($polygon['segments'] as $i => $segment) {
            $text[] = 'side ' . ($i + 1) . ' segment ' . $segment['number'] . ' length2 ' . $polygon['length2'][$i] . ' support ' . $polygon['support'][$i];
        }
    }
    writeText('polygons', $text);
    $text = ['corners ' . count($corners)];
    foreach ($corners as $corner) {
        $text[] = 'corner ' . $corner['number'] . ' ' . $corner['x'] . ' ' . $corner['y'] . ' response ' . $corner['response'] . ' match ' . $corner['match'];
    }
    writeText('corners', $text);
    $text = ['components ' . count($components)];
    foreach ($components as $component) {
        $text[] = 'component ' . $component['number'] . ' pixels ' . $component['pixels'] . ' box ' . implode(' ', $component['box']) .
            ' ends ' . $component['ends'] . ' strength ' . $component['strength'] . ' direction ' . $component['direction'] .
            ' shape ' . $component['matching'] . ' explained ' . $component['explained'];
    }
    writeText('components', $text);
}

function writeCounts(array $image, array $gradient, array $nms, array $direction, array $thresholded,
    array $circleDetection, array $circles, array $circlePixels, array $linePixels, array $vote, array $peaks,
    array $extracted, array $junctions, array $polygons, array $cornerDetection, array $components): void
{
    $edges = $thresholded['edges'];
    $strong = $thresholded['strong'];
    $weak = $thresholded['weak'];
    $corners = $cornerDetection['corners'];
    $weakKept = 0;
    $directions = [0 => 0, 45 => 0, 90 => 0, 135 => 0];
    foreach ($edges as $i => $edge) {
        if ($weak[$i] && $edge) $weakKept++;
        if ($edge) $directions[$direction[$i]]++;
    }
    $rows = ['image ' . $image['width'] . ' ' . $image['height'],
        'gradient_nonzero ' . count(array_filter($gradient['magnitude'], fn($value) => $value > 0)),
        'gradient_max ' . max($gradient['magnitude']), 'nms_kept ' . count(array_filter($nms, fn($value) => $value > 0)),
        'strong ' . array_sum($strong), 'weak ' . array_sum($weak), 'edges ' . array_sum($edges),
        'weak_kept ' . $weakKept, 'weak_dropped ' . (array_sum($weak) - $weakKept), 'edge_components ' . count($components)];
    foreach ($directions as $d => $value) $rows[] = 'direction_' . $d . ' ' . $value;
    $rows[] = 'circle_candidates ' . $circleDetection['candidates'];
    $rows[] = 'circle_peaks ' . count($circleDetection['peaks']);
    $rows[] = 'circles ' . count($circles);
    $rows[] = 'circle_edge_pixels ' . array_sum($circlePixels);
    $rows[] = 'line_edge_pixels ' . count($linePixels);
    $rows[] = 'hough_max_votes ' . $vote['maximum'];
    $rows[] = 'hough_peaks ' . count($peaks);
    $rows[] = 'lines ' . count($extracted['lines']);
    $rows[] = 'segments ' . count($extracted['segments']);
    $rows[] = 'claimed_pixels ' . array_sum($extracted['used']);
    $rows[] = 'junctions ' . $junctions['count'];
    $rows[] = 'polygons ' . count($polygons);
    foreach (['equilateral_triangle', 'right_triangle', 'triangle', 'square', 'rectangle', 'parallelogram', 'trapezoid', 'quadrilateral'] as $kind) {
        $rows[] = $kind . ' ' . count(array_filter($polygons, fn($polygon) => $polygon['kind'] === $kind));
    }
    $rows[] = 'corner_candidates ' . count($cornerDetection['candidates']);
    $rows[] = 'corners ' . count($corners);
    $rows[] = 'corners_on_vertices ' . count(array_filter($corners, fn($corner) => $corner['matchKind'] === 'polygon'));
    $rows[] = 'corners_on_segments ' . count(array_filter($corners, fn($corner) => $corner['matchKind'] === 'segment'));
    $rows[] = 'corners_unmatched ' . count(array_filter($corners, fn($corner) => $corner['matchKind'] === 'none'));
    $matchedVertices = 0;
    foreach ($polygons as $polygon) foreach ($polygon['vertexCorners'] as $corner) if ($corner !== null) $matchedVertices++;
    $rows[] = 'vertices_with_corner ' . $matchedVertices;
    writeText('report', $rows);
}

function main(): void
{
    $image = readImage('input/image.pgm');
    $trig = readTrig('input/trig.txt');
    $params = readParams('input/params.txt');
    $width = $image['width'];
    $height = $image['height'];
    $smoothed = smooth($image, $params);
    $gradient = gradient($smoothed, $width, $height);
    $direction = directions($gradient['gx'], $gradient['gy']);
    $nms = suppress($gradient['magnitude'], $direction, $width, $height);
    $thresholded = hysteresis($nms, $width, $height, $params['canny_low'], $params['canny_high']);
    $edges = $thresholded['edges'];
    $groups = edgeComponents($edges, $width, $height);
    $circleVotes = circleVotes($edges, $width, $height, $params['circle_min_radius'], $params['circle_max_radius']);
    $circleDetection = circlePeaks($circleVotes, $width, $height, $params['circle_min_percent']);
    $circles = selectCircles($circleDetection['peaks'], $edges, $width, $height, $params['circle_max_count']);
    $remaining = removeCirclePixels($edges, $circles, $width);
    $votes = lineVotes($remaining['pixels'], $trig, $params['hough_rho_step']);
    $peaks = linePeaks($votes, $params['hough_threshold']);
    $vote = voteImage($votes, $width, $height, $trig, $params['hough_rho_step']);
    $extracted = extractSegments($peaks, $remaining['pixels'], $trig, $params, count($edges));
    $junctions = findJunctions($extracted['segments'], $params);
    $polygons = findPolygons($extracted['segments'], $junctions['adjacency']);
    foreach ($polygons as &$polygon) polygonAttributes($polygon, $edges, $width, $height, $params);
    unset($polygon);
    $shapes = array_merge($polygons, $circles);
    measureShapes($shapes, $image, $params['contrast_margin']);
    $polygons = array_slice($shapes, 0, count($polygons));
    $circles = array_slice($shapes, count($polygons));
    $cornerDetection = detectCorners($gradient['gx'], $gradient['gy'], $width, $height,
        $params['harris_window'], $params['harris_threshold'], $params['harris_max_count']);
    matchCorners($cornerDetection['corners'], $polygons, $extracted['segments'], $params['corner_match_distance']);
    $shapes = array_merge($polygons, $circles);
    $components = describeComponents($groups, $edges, $gradient['magnitude'], $direction, $shapes, $width, $height);
    $overlay = overlayImage($image, $extracted['segments'], $circles, $cornerDetection['corners'], $params['overlay_divisor']);
    if (!is_dir('output')) mkdir('output', 0777, true);
    writeImage('output/edges.pgm', $width, $height, array_map(fn($value) => 255 * $value, $edges));
    writeImage('output/hough.pgm', 180, $vote['height'], $vote['pixels']);
    writeImage('output/overlay.pgm', $width, $height, $overlay);
    writeLists($extracted['lines'], $circles, $polygons, $cornerDetection['corners'], $components);
    writeCounts($image, $gradient, $nms, $direction, $thresholded, $circleDetection, $circles,
        $remaining['removed'], $remaining['pixels'], $vote, $peaks, $extracted, $junctions, $polygons, $cornerDetection, $components);
}

main();
