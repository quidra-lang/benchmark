<?php

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/kdtree.php';
require_once __DIR__ . '/quadtree.php';
require_once __DIR__ . '/rtree.php';
require_once __DIR__ . '/grid.php';
require_once __DIR__ . '/report.php';

const POINT_STRUCTURES = ['kdtree', 'quadtree', 'rtree', 'str', 'grid'];
const RECTANGLE_STRUCTURES = ['rtree_rect', 'str_rect'];
const TREE_STRUCTURES = ['kdtree', 'quadtree', 'rtree', 'str', 'rtree_rect', 'str_rect'];
const SEARCH_COMMANDS = ['RANGE', 'RADIUS', 'KNN', 'WINDOWCOUNT', 'CONTAINS', 'NEAREST', 'JOIN'];

function fields(...$values) {
    return implode(' ', $values);
}

function distance($x, $y, $point) {
    return ($point['x'] - $x) * ($point['x'] - $x) + ($point['y'] - $y) * ($point['y'] - $y);
}

function minimumDistance($x, $y, $box) {
    $dx = $x < $box[0] ? $box[0] - $x : ($x > $box[2] ? $x - $box[2] : 0);
    $dy = $y < $box[1] ? $box[1] - $y : ($y > $box[3] ? $y - $box[3] : 0);
    return $dx * $dx + $dy * $dy;
}

function makeView($source, $region, $held, $children, $depth, $mark) {
    $count = count($held);
    foreach ($children as $child) $count += $child['count'];
    return compact('source', 'region', 'held', 'children', 'count', 'depth', 'mark');
}

function kdView($node, $region, $depth = 0, $mark = 'root') {
    $children = [];
    $split = $node->axis === 0 ? $node->point['x'] : $node->point['y'];
    if ($node->left !== null) {
        $bounds = $region;
        $bounds[$node->axis + 2] = $split;
        $children[] = kdView($node->left, $bounds, $depth + 1, 'L');
    }
    if ($node->right !== null) {
        $bounds = $region;
        $bounds[$node->axis] = $split;
        $children[] = kdView($node->right, $bounds, $depth + 1, 'R');
    }
    return makeView($node, $region, [$node->point], $children, $depth, $mark);
}

function quadView($node, $depth = 0, $mark = 'root') {
    $region = [$node->x, $node->y, $node->x + $node->size - 1, $node->y + $node->size - 1];
    $children = [];
    if ($node->children !== null) foreach ($node->children as $i => $child) $children[] = quadView($child, $depth + 1, QUAD_NAMES[$i]);
    return makeView($node, $region, $node->points, $children, $depth, $mark);
}

function rtreeView($node, $depth = 0) {
    $children = $held = [];
    if ($node->level > 0) foreach ($node->entries as $entry) $children[] = rtreeView($entry['child'], $depth + 1);
    else foreach ($node->entries as $entry) $held[] = $entry['object'];
    return makeView($node, nodeBox($node), $held, $children, $depth, '');
}

function gridView($grid, $world) {
    $children = [];
    foreach ($grid->cells as $cell) {
        $x = $cell->column * $grid->size;
        $y = $cell->row * $grid->size;
        $children[] = makeView($cell, [$x, $y, $x + $grid->size - 1, $y + $grid->size - 1], $cell->points, [], 1, '');
    }
    return makeView($grid, [0, 0, $world - 1, $world - 1], [], $children, 0, '');
}

function currentViews(&$state) {
    if ($state['views'] !== null) return $state['views'];
    $world = $state['settings']['world'];
    $structures = $state['structures'];
    $views = ['kdtree' => kdView($structures['kdtree']->root, [0, 0, $world - 1, $world - 1]),
        'quadtree' => quadView($structures['quadtree']->root), 'grid' => gridView($structures['grid'], $world)];
    foreach (['rtree', 'str', 'rtree_rect', 'str_rect'] as $name) $views[$name] = rtreeView($structures[$name]->root);
    $state['views'] = $views;
    return $views;
}

function conditionSearch($root, $regionCondition, $objectCondition) {
    $answer = [];
    $nodes = $tests = 0;
    $pending = [$root];
    while ($pending) {
        $node = array_pop($pending);
        $nodes++;
        $tests += count($node['held']);
        foreach ($node['held'] as $object) if ($objectCondition($object)) $answer[] = $object['id'];
        for ($i = count($node['children']) - 1; $i >= 0; $i--) {
            $child = $node['children'][$i];
            if ($regionCondition($child['region'])) $pending[] = $child;
        }
    }
    sort($answer, SORT_NUMERIC);
    return compact('answer', 'nodes', 'tests');
}

function windowCount($root, $window) {
    $answer = $nodes = $tests = 0;
    $pending = [$root];
    while ($pending) {
        $node = array_pop($pending);
        $nodes++;
        if (contains($window, $node['region'])) {
            $answer += $node['count'];
            continue;
        }
        $tests += count($node['held']);
        foreach ($node['held'] as $point) if (contains($window, $point['box'])) $answer++;
        for ($i = count($node['children']) - 1; $i >= 0; $i--) {
            $child = $node['children'][$i];
            if (intersects($child['region'], $window)) $pending[] = $child;
        }
    }
    return compact('answer', 'nodes', 'tests');
}

class PriorityQueue {
    private $entries = [];

    public function push($entry) {
        $index = count($this->entries);
        $this->entries[] = $entry;
        while ($index > 0) {
            $parent = intdiv($index - 1, 2);
            if (compareTuple($this->entries[$parent]['key'], $entry['key']) < 0) break;
            $this->entries[$index] = $this->entries[$parent];
            $index = $parent;
        }
        $this->entries[$index] = $entry;
    }

    public function pop() {
        $first = $this->entries[0];
        $last = array_pop($this->entries);
        if (!$this->entries) return $first;
        $index = 0;
        while (2 * $index + 1 < count($this->entries)) {
            $child = 2 * $index + 1;
            if ($child + 1 < count($this->entries) && compareTuple($this->entries[$child + 1]['key'], $this->entries[$child]['key']) < 0) $child++;
            if (compareTuple($last['key'], $this->entries[$child]['key']) < 0) break;
            $this->entries[$index] = $this->entries[$child];
            $index = $child;
        }
        $this->entries[$index] = $last;
        return $first;
    }
}

function nearestSearch($root, $x, $y, $count, $rectangles) {
    $pending = new PriorityQueue();
    $serial = 0;
    $enqueue = function($node) use ($pending, $x, $y, &$serial) {
        $pending->push(['key' => [minimumDistance($x, $y, $node['region']), 0, $serial++], 'node' => $node]);
    };
    $enqueue($root);
    $nodes = $tests = 0;
    $answer = [];
    while (count($answer) < $count) {
        $entry = $pending->pop();
        if (isset($entry['object'])) {
            $answer[] = [$entry['object']['id'], $entry['key'][0]];
            continue;
        }
        $node = $entry['node'];
        $nodes++;
        $tests += count($node['held']);
        foreach ($node['held'] as $object) {
            $value = $rectangles ? minimumDistance($x, $y, $object['box']) : distance($x, $y, $object);
            $pending->push(['key' => [$value, 1, $object['id']], 'object' => $object]);
        }
        foreach ($node['children'] as $child) $enqueue($child);
    }
    return compact('answer', 'nodes', 'tests');
}

function spatialJoin($pointRoot, $rectangleRoot) {
    $answer = [];
    $nodes = $tests = 0;
    $visit = function($points, $rectangles) use (&$visit, &$answer, &$nodes, &$tests) {
        $nodes++;
        if (!$points['children'] && !$rectangles['children']) {
            $tests += count($points['held']) * count($rectangles['held']);
            foreach ($points['held'] as $point) foreach ($rectangles['held'] as $rectangle) {
                if (contains($rectangle['box'], $point['box'])) $answer[] = [$rectangle['id'], $point['id']];
            }
        } elseif (!$points['children']) {
            foreach ($rectangles['children'] as $child) if (intersects($child['region'], $points['region'])) $visit($points, $child);
        } elseif (!$rectangles['children']) {
            foreach ($points['children'] as $child) if (intersects($child['region'], $rectangles['region'])) $visit($child, $rectangles);
        } else {
            foreach ($points['children'] as $pointChild) foreach ($rectangles['children'] as $rectangleChild) {
                if (intersects($pointChild['region'], $rectangleChild['region'])) $visit($pointChild, $rectangleChild);
            }
        }
    };
    $visit($pointRoot, $rectangleRoot);
    usort($answer, 'compareTuple');
    return compact('answer', 'nodes', 'tests');
}

function searchNames($command) {
    if ($command === 'JOIN') return ['rtree', 'str'];
    return $command === 'CONTAINS' || $command === 'NEAREST' ? RECTANGLE_STRUCTURES : POINT_STRUCTURES;
}

function search($root, $command, $args) {
    [$x, $y] = $args;
    switch ($command) {
        case 'RANGE':
            return conditionSearch($root, fn($region) => intersects($region, $args), fn($object) => contains($args, $object['box']));
        case 'RADIUS':
            $squared = $args[2] * $args[2];
            return conditionSearch($root, fn($region) => minimumDistance($x, $y, $region) <= $squared, fn($object) => distance($x, $y, $object) <= $squared);
        case 'CONTAINS':
            $box = [$x, $y, $x, $y];
            return conditionSearch($root, fn($region) => contains($region, $box), fn($object) => contains($object['box'], $box));
        case 'WINDOWCOUNT': return windowCount($root, $args);
        case 'KNN': return nearestSearch($root, $x, $y, $args[2], false);
        case 'NEAREST': return nearestSearch($root, $x, $y, $args[2], true);
    }
}

function bruteForce($state, $command, $args) {
    $points = array_values($state['points']);
    usort($points, fn($a, $b) => $a['id'] <=> $b['id']);
    $x = $args[0] ?? 0;
    $y = $args[1] ?? 0;
    if ($command === 'RANGE' || $command === 'RADIUS' || $command === 'WINDOWCOUNT') {
        $answer = [];
        foreach ($points as $point) {
            $match = $command === 'RADIUS' ? distance($x, $y, $point) <= $args[2] * $args[2] : contains($args, $point['box']);
            if ($match) $answer[] = $point['id'];
        }
        return $command === 'WINDOWCOUNT' ? count($answer) : $answer;
    }
    if ($command === 'CONTAINS') {
        $answer = [];
        foreach ($state['rectangles'] as $rectangle) if (contains($rectangle['box'], [$x, $y, $x, $y])) $answer[] = $rectangle['id'];
        return $answer;
    }
    if ($command === 'KNN' || $command === 'NEAREST') {
        $answer = [];
        $objects = $command === 'KNN' ? $points : $state['rectangles'];
        foreach ($objects as $object) {
            $value = $command === 'KNN' ? distance($x, $y, $object) : minimumDistance($x, $y, $object['box']);
            $answer[] = [$object['id'], $value];
        }
        usort($answer, fn($a, $b) => ($a[1] <=> $b[1]) ?: ($a[0] <=> $b[0]));
        return array_slice($answer, 0, $args[2]);
    }
    $pairs = [];
    foreach ($state['rectangles'] as $rectangle) foreach ($points as $point) {
        if (contains($rectangle['box'], $point['box'])) $pairs[] = [$rectangle['id'], $point['id']];
    }
    return $pairs;
}

function recordVisit(&$state, $query, $command, $name, $result) {
    $state['visits'][] = implode(',', [$query, $command, $name, $result['nodes'], $result['tests']]);
    if (!isset($state['totals'][$command][$name])) $state['totals'][$command][$name] = ['queries' => 0, 'nodes' => 0, 'tests' => 0, 'maximum' => 0];
    $total = &$state['totals'][$command][$name];
    $total['queries']++;
    $total['nodes'] += $result['nodes'];
    $total['tests'] += $result['tests'];
    $total['maximum'] = max($total['maximum'], $result['nodes']);
}

function executeSearch(&$state, $query, $command, $args) {
    $expected = bruteForce($state, $command, $args);
    $views = currentViews($state);
    $mismatches = [];
    foreach (searchNames($command) as $name) {
        $result = $command === 'JOIN' ? spatialJoin($views[$name], $views[$name . '_rect']) : search($views[$name], $command, $args);
        recordVisit($state, $query, $command, $name, $result);
        if ($result['answer'] !== $expected) $mismatches[] = $name;
    }
    $check = $mismatches ? 'mismatch ' . implode(' ', $mismatches) : 'ok';
    if ($command === 'WINDOWCOUNT') return fields($query, $command, 'count', $expected, 'check', $check);
    if ($command === 'JOIN') {
        foreach ($expected as $pair) $state['joins'][] = implode(',', [$query, $pair[0], $pair[1]]);
        return fields($query, $command, 'count', count($expected), 'check', $check);
    }
    $values = $expected;
    if ($command === 'KNN' || $command === 'NEAREST') $values = array_map(fn($pair) => implode(':', $pair), $expected);
    return fields($query, $command, 'count', count($expected), 'ids', ids($values), 'check', $check);
}

function preorder($root) {
    $nodes = [];
    $pending = [$root];
    while ($pending) {
        $node = array_pop($pending);
        $nodes[] = $node;
        for ($i = count($node['children']) - 1; $i >= 0; $i--) $pending[] = $node['children'][$i];
    }
    return $nodes;
}

function dumpTree($name, $root) {
    $lines = [];
    foreach (preorder($root) as $view) {
        $node = $view['source'];
        if ($name === 'kdtree') {
            $line = fields($view['mark'], $node->axis === 0 ? 'x' : 'y', $node->point['id'], $node->point['x'], $node->point['y'], 'box', ...$view['region']);
        } elseif ($name === 'quadtree') {
            $detail = $node->children !== null ? fields('node count', $view['count']) : fields('leaf', ids(array_column($view['held'], 'id')));
            $line = fields($view['mark'], $node->x, $node->y, $node->size, $detail);
        } elseif ($node->level === 0) {
            $line = fields('leaf', ...array_merge($view['region'], ['ids', ids(array_column($view['held'], 'id'))]));
        } else {
            $line = fields('node', $node->level, ...array_merge($view['region'], ['entries', count($node->entries)]));
        }
        $lines[] = str_repeat(' ', 2 * ($view['depth'] + 1)) . $line;
    }
    return $lines;
}

function kdStatistics($root) {
    $nodes = preorder($root);
    $depths = [];
    $leaves = $oneChild = $depthSum = 0;
    foreach ($nodes as $node) {
        $depth = $node['depth'];
        if (!isset($depths[$depth])) $depths[$depth] = ['nodes' => 0, 'leaves' => 0, 'oneChild' => 0];
        $depths[$depth]['nodes']++;
        $depthSum += $depth;
        if (!count($node['children'])) {
            $depths[$depth]['leaves']++;
            $leaves++;
        } elseif (count($node['children']) === 1) {
            $depths[$depth]['oneChild']++;
            $oneChild++;
        }
    }
    ksort($depths, SORT_NUMERIC);
    $ideal = 0;
    while ((1 << $ideal) - 1 < count($nodes)) $ideal++;
    $lines = [fields('kdtree height', count($depths), 'ideal', $ideal, 'nodes', count($nodes), 'leaves', $leaves, 'one_child', $oneChild, 'depth_sum', $depthSum, 'avg_depth', fraction($depthSum, count($nodes)))];
    foreach ($depths as $depth => $value) $lines[] = '  ' . fields('depth', $depth, 'nodes', $value['nodes'], 'leaves', $value['leaves'], 'one_child', $value['oneChild']);
    return $lines;
}

function quadStatistics($root, $bucket) {
    $depths = [];
    $internal = $leaves = $empty = $maximum = 0;
    foreach (preorder($root) as $node) {
        $depth = $node['depth'];
        if (!isset($depths[$depth])) $depths[$depth] = ['internal' => 0, 'leaves' => 0, 'points' => 0];
        if ($node['children']) {
            $depths[$depth]['internal']++;
            $internal++;
        } else {
            $depths[$depth]['leaves']++;
            $depths[$depth]['points'] += count($node['held']);
            $leaves++;
            if (!$node['held']) $empty++;
            $maximum = max($maximum, count($node['held']));
        }
    }
    ksort($depths, SORT_NUMERIC);
    $lines = [fields('quadtree height', count($depths), 'internal', $internal, 'leaves', $leaves, 'empty', $empty, 'max_leaf', $maximum, 'fill', fraction($root['count'], $leaves * $bucket))];
    foreach ($depths as $depth => $value) $lines[] = '  ' . fields('depth', $depth, 'internal', $value['internal'], 'leaves', $value['leaves'], 'points', $value['points']);
    return $lines;
}

function rtreeStatistics($name, $root, $settings) {
    $nodes = preorder($root);
    $height = $root['source']->level + 1;
    $levels = array_fill(0, $height, []);
    $leaves = $entries = 0;
    foreach ($nodes as $node) {
        $levels[$node['source']->level][] = $node;
        $entries += count($node['source']->entries);
        if ($node['source']->level === 0) $leaves++;
    }
    $lines = [fields($name, 'height', $height, 'nodes', count($nodes), 'leaves', $leaves, 'entries', $entries, 'fill', fraction($entries, count($nodes) * $settings['maximum']))];
    for ($level = $height - 1; $level >= 0; $level--) {
        $group = $levels[$level];
        $totalEntries = $maximum = $under = $totalArea = $totalOverlap = 0;
        $minimum = PHP_INT_MAX;
        foreach ($group as $i => $node) {
            $count = count($node['source']->entries);
            $totalEntries += $count;
            $minimum = min($minimum, $count);
            $maximum = max($maximum, $count);
            if ($count < $settings['minimum']) $under++;
            $totalArea += area($node['region']);
            for ($j = $i + 1; $j < count($group); $j++) $totalOverlap += overlap($node['region'], $group[$j]['region']);
        }
        $lines[] = '  ' . fields('level', $level, 'nodes', count($group), 'entries', $totalEntries, 'min', $minimum, 'max', $maximum, 'under', $under, 'area', $totalArea, 'overlap', $totalOverlap);
    }
    return $lines;
}

function gridStatistics($root) {
    $occupancy = [];
    $used = $maximum = 0;
    foreach ($root['children'] as $cell) {
        $count = count($cell['held']);
        $occupancy[$count] = ($occupancy[$count] ?? 0) + 1;
        if ($count > 0) $used++;
        $maximum = max($maximum, $count);
    }
    ksort($occupancy, SORT_NUMERIC);
    $counts = [];
    foreach ($occupancy as $count => $frequency) $counts[] = $count . ':' . $frequency;
    return [fields('grid cells', count($root['children']), 'used', $used, 'max', $maximum), '  ' . fields('occupancy', ...$counts)];
}

function snapshot(&$state, $query) {
    $number = $state['snapshots']++;
    $views = currentViews($state);
    $header = fields('snapshot', $number, 'query', $query, 'points', count($state['points']), 'rects', count($state['rectangles']));
    if ($number > 0) {
        $state['dumps'][] = '';
        $state['statistics'][] = '';
    }
    $state['dumps'][] = $header;
    $state['statistics'][] = $header;
    foreach (TREE_STRUCTURES as $name) {
        $state['dumps'][] = $name;
        foreach (dumpTree($name, $views[$name]) as $line) $state['dumps'][] = $line;
    }
    foreach (kdStatistics($views['kdtree']) as $line) $state['statistics'][] = $line;
    foreach (quadStatistics($views['quadtree'], $state['settings']['bucket']) as $line) $state['statistics'][] = $line;
    foreach (['rtree', 'str', 'rtree_rect', 'str_rect'] as $name) {
        foreach (rtreeStatistics($name, $views[$name], $state['settings']) as $line) $state['statistics'][] = $line;
    }
    foreach (gridStatistics($views['grid']) as $line) $state['statistics'][] = $line;
    return $number;
}

function locateKD($node, $point) {
    $path = '';
    while ($node->point['id'] !== $point['id']) {
        $left = kdCompare($point, $node->point, $node->axis) < 0;
        $path .= $left ? 'L' : 'R';
        $node = $left ? $node->left : $node->right;
    }
    return $path !== '' ? $path : '-';
}

function locateQuad($node, $point) {
    $path = [];
    while ($node->children !== null) {
        $child = quadDestination($node, $point);
        $path[] = QUAD_NAMES[$child];
        $node = $node->children[$child];
    }
    return $path ? implode('/', $path) : '-';
}

function locateRTree($node, $point) {
    if ($node->level === 0) {
        foreach ($node->entries as $i => $entry) if ($entry['object']['id'] === $point['id']) return [$i + 1];
        return null;
    }
    foreach ($node->entries as $i => $entry) {
        if (!contains($entry['box'], $point['box'])) continue;
        $found = locateRTree($entry['child'], $point);
        if ($found !== null) return array_merge([$i + 1], $found);
    }
    return null;
}

function locate($state, $query, $id) {
    if (!isset($state['points'][$id])) return fields($query, 'LOCATE', $id, 'missing');
    $point = $state['points'][$id];
    $structures = $state['structures'];
    $cell = $structures['grid']->cell($point);
    return fields($query, 'LOCATE', $id, 'kdtree', locateKD($structures['kdtree']->root, $point),
        'quadtree', locateQuad($structures['quadtree']->root, $point), 'rtree', implode('/', locateRTree($structures['rtree']->root, $point)),
        'str', implode('/', locateRTree($structures['str']->root, $point)), 'grid', $cell->column, $cell->row);
}

function updatePoint(&$state, $query, $command, $args) {
    $id = $args[0];
    if ($command === 'INSERT') {
        $point = makePoint(...$args);
        foreach (POINT_STRUCTURES as $name) $state['structures'][$name]->insert($point);
        $state['points'][$id] = $point;
        $state['views'] = null;
        return fields($query, $command, $id, 'inserted points', count($state['points']));
    }
    if (!isset($state['points'][$id])) return fields($query, $command, $id, 'missing points', count($state['points']));
    $point = $state['points'][$id];
    foreach (POINT_STRUCTURES as $name) $state['structures'][$name]->remove($point);
    unset($state['points'][$id]);
    $state['views'] = null;
    return fields($query, $command, $id, 'deleted points', count($state['points']));
}

function visitSummary($state) {
    $lines = ['visits'];
    foreach (SEARCH_COMMANDS as $command) {
        if (!isset($state['totals'][$command])) continue;
        $totals = $state['totals'][$command];
        $names = searchNames($command);
        $ranking = [];
        foreach ($names as $index => $name) {
            $total = $totals[$name];
            $lines[] = fields($command, $name, 'queries', $total['queries'], 'nodes', $total['nodes'], 'tests', $total['tests'], 'max_nodes', $total['maximum'], 'mean_nodes', fraction($total['nodes'], $total['queries']));
            $ranking[] = ['name' => $name, 'index' => $index, 'nodes' => $total['nodes'], 'tests' => $total['tests']];
        }
        usort($ranking, fn($a, $b) => ($a['nodes'] <=> $b['nodes']) ?: (($a['tests'] <=> $b['tests']) ?: ($a['index'] <=> $b['index'])));
        $lines[] = fields('rank', $command, ...array_column($ranking, 'name'));
    }
    return $lines;
}

function initialize($data) {
    $points = $data['points'];
    $rectangles = $data['rectangles'];
    $settings = $data['settings'];
    $structures = ['kdtree' => new KDTree($points), 'quadtree' => new QuadTree($points, $settings['world'], $settings['bucket']),
        'rtree' => new RTree($points, $settings['maximum'], $settings['minimum']), 'str' => new RTree($points, $settings['maximum'], $settings['minimum'], true),
        'grid' => new Grid($points, $settings['world'], $settings['cell']), 'rtree_rect' => new RTree($rectangles, $settings['maximum'], $settings['minimum']),
        'str_rect' => new RTree($rectangles, $settings['maximum'], $settings['minimum'], true)];
    $pointMap = [];
    foreach ($points as $point) $pointMap[$point['id']] = $point;
    usort($rectangles, fn($a, $b) => $a['id'] <=> $b['id']);
    return ['structures' => $structures, 'settings' => $settings, 'points' => $pointMap, 'rectangles' => $rectangles, 'views' => null, 'snapshots' => 0,
        'answers' => [], 'visits' => ['query,command,structure,nodes,tests'], 'joins' => ['query,rect,point'], 'dumps' => [], 'statistics' => [], 'totals' => []];
}

$data = readDataset();
$state = initialize($data);
snapshot($state, 0);
foreach ($data['commands'] as $index => $command) {
    $query = $index + 1;
    $name = $command['name'];
    $args = $command['args'];
    if (in_array($name, SEARCH_COMMANDS, true)) $answer = executeSearch($state, $query, $name, $args);
    elseif ($name === 'LOCATE') $answer = locate($state, $query, $args[0]);
    elseif ($name === 'DUMP') $answer = fields($query, 'DUMP snapshot', snapshot($state, $query));
    else $answer = updatePoint($state, $query, $name, $args);
    $state['answers'][] = $answer;
}
$state['statistics'][] = '';
foreach (visitSummary($state) as $line) $state['statistics'][] = $line;
writeLines('answers.txt', $state['answers']);
writeLines('visits.csv', $state['visits']);
writeLines('join.csv', $state['joins']);
writeLines('structures.txt', $state['dumps']);
writeLines('stats.txt', $state['statistics']);
