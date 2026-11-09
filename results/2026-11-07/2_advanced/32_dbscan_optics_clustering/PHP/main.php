<?php

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/grid_index.php';
require_once __DIR__ . '/dbscan.php';
require_once __DIR__ . '/optics.php';
require_once __DIR__ . '/report.php';

function character(int $label): string
{
    return $label < 0 ? '.' : ($label < 26 ? chr(65 + $label) : ($label < 52 ? chr(97 + $label - 26) : '#'));
}

function distanceMatrix(array $points): array
{
    $distances = [];
    foreach ($points as $first) {
        $row = '';
        foreach ($points as $second) {
            $row .= pack('V', squaredDistance($first, $second));
        }
        $distances[] = $row;
    }
    return $distances;
}

function ceilingRoot(int $value): int
{
    $low = $high = 1;
    while ($high * $high < $value) {
        $high *= 2;
    }
    while ($low < $high) {
        $middle = intdiv($low + $high, 2);
        if ($middle * $middle >= $value) {
            $high = $middle;
        } else {
            $low = $middle + 1;
        }
    }
    return $low;
}

function kneeCurves(array $distances, int $minimum): object
{
    $neighbors = [];
    foreach ($distances as $p => $_) {
        $row = [];
        foreach ($distances as $q => $_) {
            if ($q !== $p) {
                $row[] = distanceAt($distances, $p, $q);
            }
        }
        sort($row, SORT_NUMERIC);
        $neighbors[] = array_slice($row, 0, 2 * $minimum);
    }
    $curves = [];
    for ($j = 1; $j <= 2 * $minimum; $j++) {
        $values = array_map(fn($row) => $row[$j - 1], $neighbors);
        $order = range(0, count($values) - 1);
        usort($order, fn($a, $b) => ($values[$b] <=> $values[$a]) ?: ($a <=> $b));
        $first = $values[$order[0]];
        $last = $values[$order[count($order) - 1]];
        $knee = 0;
        $cross = -1;
        foreach ($order as $position => $p) {
            $value = abs((count($order) - 1) * ($values[$p] - $first) - ($last - $first) * $position);
            if ($value > $cross) {
                $knee = $position;
                $cross = $value;
            }
        }
        $curves[] = (object) ['j' => $j, 'values' => $values, 'order' => $order, 'knee' => $knee,
            'cross' => $cross, 'radius' => ceilingRoot($values[$order[$knee]])];
    }
    return (object) ['curves' => $curves, 'kdist' => $curves[$minimum - 2]];
}

function extractOptics(object $ordering, int $radius): object
{
    $labels = array_fill(0, count($ordering->ordering), -1);
    $limit = $radius * $radius;
    $cluster = -1;
    foreach ($ordering->ordering as $p) {
        if ($ordering->reach[$p] > $limit) {
            if ($ordering->core[$p] <= $limit) {
                $labels[$p] = ++$cluster;
            }
        } else {
            $labels[$p] = $cluster;
        }
    }
    $core = array_map(fn($value) => $value <= $limit, $ordering->core);
    return (object) compact('labels', 'core');
}

function xiExtraction(object $ordering, object $parameters): object
{
    $count = count($ordering->ordering);
    $reach = [INF];
    foreach ($ordering->ordering as $p) {
        $reach[] = $ordering->reach[$p];
    }
    $reach[] = INF;
    [$u, $v] = $parameters->xi;
    $alpha = ($v - $u) * ($v - $u);
    $beta = $v * $v;
    $xle = fn($a, $b) => $b === INF || ($a !== INF && $beta * $a <= $alpha * $b);
    $positions = [];
    for ($i = 1; $i <= $count; $i++) {
        $a = $reach[$i];
        $b = $reach[$i + 1];
        $defined = $a !== INF || $b !== INF;
        $steepUp = $defined && $xle($a, $b);
        $steepDown = $defined && $xle($b, $a);
        $positions[$i] = (object) ['steepUp' => $steepUp, 'steepDown' => $steepDown,
            'up' => $steepUp || $a < $b, 'down' => $steepDown || $a > $b];
    }
    $regionEnd = function (int $start, bool $down) use ($positions, $count, $parameters): int {
        $end = $start;
        $flat = 0;
        for ($i = $start; $i <= $count; $i++) {
            $position = $positions[$i];
            if ($down ? $position->steepDown : $position->steepUp) {
                $end = $i;
                $flat = 0;
            } elseif ($down ? $position->up : $position->down) {
                break;
            } elseif (++$flat > $parameters->minimum) {
                break;
            }
        }
        return $end;
    };
    $downAreas = $steepAreas = $clusters = [];
    $index = 1;
    $between = 0;
    for ($s = 1; $s <= $count; $s++) {
        if ($s < $index || (!$positions[$s]->steepUp && !$positions[$s]->steepDown)) {
            continue;
        }
        for ($i = $index; $i <= $s; $i++) {
            $between = max($between, $reach[$i]);
        }
        if ($between === INF) {
            $downAreas = [];
        } else {
            $downAreas = array_values(array_filter($downAreas, fn($area) => $xle($between, $reach[$area->start])));
            foreach ($downAreas as $area) {
                $area->maximum = max($area->maximum, $between);
            }
        }
        if ($positions[$s]->steepDown) {
            $end = $regionEnd($s, true);
            $downAreas[] = (object) ['start' => $s, 'end' => $end, 'maximum' => 0];
            $steepAreas[] = (object) ['direction' => 'down', 'start' => $s, 'end' => $end];
            $index = $end + 1;
            $between = $reach[$index];
        } else {
            $end = $regionEnd($s, false);
            $steepAreas[] = (object) ['direction' => 'up', 'start' => $s, 'end' => $end];
            $index = $end + 1;
            $between = $reach[$index];
            $candidates = [];
            foreach ($downAreas as $area) {
                $start = $area->start;
                $finish = $end;
                if (!$xle($area->maximum, $reach[$finish + 1])) {
                    continue;
                }
                $down = $reach[$area->start];
                if ($xle($reach[$finish + 1], $down)) {
                    while ($reach[$start + 1] > $reach[$finish + 1] && $start < $area->end) {
                        $start++;
                    }
                } elseif ($xle($down, $reach[$finish + 1])) {
                    while ($reach[$finish - 1] > $down && $finish > $s) {
                        $finish--;
                    }
                }
                if ($finish - $start + 1 >= $parameters->minimumSize && $start <= $area->end && $finish >= $s) {
                    $candidates[] = (object) ['start' => $start, 'end' => $finish, 'size' => $finish - $start + 1, 'label' => null, 'parent' => null];
                }
            }
            array_push($clusters, ...array_reverse($candidates));
        }
    }
    $labels = array_fill(0, $count, -1);
    $nextLabel = 0;
    foreach ($clusters as $cluster) {
        $free = true;
        for ($i = $cluster->start; $i <= $cluster->end; $i++) {
            if ($labels[$ordering->ordering[$i - 1]] !== -1) {
                $free = false;
            }
        }
        if ($free) {
            $cluster->label = $nextLabel++;
            for ($i = $cluster->start; $i <= $cluster->end; $i++) {
                $labels[$ordering->ordering[$i - 1]] = $cluster->label;
            }
        }
    }
    foreach ($clusters as $j => $cluster) {
        foreach ($clusters as $i => $candidate) {
            if ($i === $j || $candidate->start > $cluster->start || $candidate->end < $cluster->end ||
                !($candidate->size > $cluster->size || ($candidate->size === $cluster->size && $i > $j))) {
                continue;
            }
            if ($cluster->parent === null || $candidate->size < $clusters[$cluster->parent]->size) {
                $cluster->parent = $i;
            }
        }
        $cluster->left = $reach[$cluster->start];
        $cluster->right = $reach[$cluster->end + 1];
        $cluster->valley = INF;
        for ($i = $cluster->start + 1; $i <= $cluster->end; $i++) {
            $cluster->valley = min($cluster->valley, $reach[$i]);
        }
    }
    $core = array_map(fn($value) => $value !== INF, $ordering->core);
    return (object) compact('labels', 'core', 'clusters', 'steepAreas');
}

function convexHull(array $members, array $points): array
{
    $sorted = $members;
    usort($sorted, fn($a, $b) => ($points[$a]->x <=> $points[$b]->x) ?: ($points[$a]->y <=> $points[$b]->y));
    if (count($sorted) <= 2) {
        return $sorted;
    }
    $turn = fn($o, $a, $b) => ($points[$a]->x - $points[$o]->x) * ($points[$b]->y - $points[$o]->y) -
        ($points[$a]->y - $points[$o]->y) * ($points[$b]->x - $points[$o]->x);
    $chain = function (array $sequence) use ($turn): array {
        $result = [];
        foreach ($sequence as $p) {
            while (count($result) >= 2 && $turn($result[count($result) - 2], $result[count($result) - 1], $p) <= 0) {
                array_pop($result);
            }
            $result[] = $p;
        }
        array_pop($result);
        return $result;
    };
    return array_merge($chain($sorted), $chain(array_reverse($sorted)));
}

function summarize(object $setting, array $points, array $distances): object
{
    $clusters = array_fill(0, max($setting->labels) + 1, []);
    foreach ($setting->labels as $p => $label) {
        if ($label >= 0) {
            $clusters[$label][] = $p;
        }
    }
    $summaries = [];
    foreach ($clusters as $members) {
        $x = $y = $core = 0;
        $xmin = $xmax = $points[$members[0]]->x;
        $ymin = $ymax = $points[$members[0]]->y;
        foreach ($members as $p) {
            $x += $points[$p]->x;
            $y += $points[$p]->y;
            $core += (int) $setting->core[$p];
            $xmin = min($xmin, $points[$p]->x);
            $xmax = max($xmax, $points[$p]->x);
            $ymin = min($ymin, $points[$p]->y);
            $ymax = max($ymax, $points[$p]->y);
        }
        $medoid = null;
        $nearest = INF;
        foreach ($members as $p) {
            $dx = count($members) * $points[$p]->x - $x;
            $dy = count($members) * $points[$p]->y - $y;
            $value = $dx * $dx + $dy * $dy;
            if ($value < $nearest) {
                $nearest = $value;
                $medoid = $p;
            }
        }
        $hull = convexHull($members, $points);
        $twiceArea = $diameter = 0;
        foreach ($hull as $i => $point) {
            $a = $points[$point];
            $b = $points[$hull[($i + 1) % count($hull)]];
            $twiceArea += $a->x * $b->y - $b->x * $a->y;
            for ($j = $i + 1; $j < count($hull); $j++) {
                $diameter = max($diameter, distanceAt($distances, $point, $hull[$j]));
            }
        }
        $summaries[] = (object) ['members' => $members, 'size' => count($members), 'core' => $core, 'border' => count($members) - $core,
            'x' => $x, 'y' => $y, 'medoid' => $medoid, 'xmin' => $xmin, 'ymin' => $ymin, 'xmax' => $xmax, 'ymax' => $ymax,
            'area' => ($xmax - $xmin + 1) * ($ymax - $ymin + 1), 'hull' => $hull, 'twiceArea' => abs($twiceArea), 'diameter' => $diameter];
    }
    $setting->clusters = $summaries;
    $setting->noise = count(array_filter($setting->labels, fn($label) => $label === -1));
    $setting->coreCount = array_sum(array_map(fn($cluster) => $cluster->core, $summaries));
    $setting->borderCount = count($points) - $setting->noise - $setting->coreCount;
    return $setting;
}

function checkDbscan(object $setting, array $neighborhoods): object
{
    $checks = [true, true, true];
    $isolated = 0;
    $ambiguous = [];
    foreach ($setting->labels as $p => $label) {
        $coreNeighbors = array_values(array_filter($neighborhoods[$p], fn($q) => $setting->core[$q]));
        if ($setting->core[$p]) {
            foreach ($coreNeighbors as $q) {
                if ($setting->labels[$q] !== $label) {
                    $checks[0] = false;
                }
            }
        } elseif ($label >= 0) {
            $same = false;
            $others = [];
            foreach ($coreNeighbors as $q) {
                if ($setting->labels[$q] === $label) {
                    $same = true;
                } else {
                    $others[$setting->labels[$q]] = true;
                }
            }
            if (!$same) {
                $checks[1] = false;
            }
            if ($others) {
                $numbers = array_keys($others);
                sort($numbers, SORT_NUMERIC);
                $ambiguous[] = (object) ['point' => $p, 'others' => $numbers];
            }
        } else {
            if ($coreNeighbors) {
                $checks[2] = false;
            }
            if (count($neighborhoods[$p]) === 1) {
                $isolated++;
            }
        }
    }
    return (object) compact('checks', 'isolated', 'ambiguous');
}

function containmentLines(array $settings): array
{
    $ordered = [];
    foreach ($settings as $index => $setting) {
        $ordered[] = (object) compact('setting', 'index');
    }
    usort($ordered, fn($a, $b) => ($a->setting->radius <=> $b->setting->radius) ?: ($a->index <=> $b->index));
    $lines = ['hierarchy'];
    for ($i = 1; $i < count($ordered); $i++) {
        $first = $ordered[$i - 1]->setting;
        $second = $ordered[$i]->setting;
        $sources = array_fill(0, count($second->clusters), []);
        foreach ($first->clusters as $c => $cluster) {
            foreach ($cluster->members as $point) {
                if ($first->core[$point]) {
                    $sources[$second->labels[$point]][] = $c;
                    break;
                }
            }
        }
        $lines[] = $first->name . ' -> ' . $second->name;
        foreach ($sources as $c => $source) {
            $lines[] = '  ' . $c . ' <- ' . ($source ? implode(' ', $source) : '-');
        }
    }
    return $lines;
}

function comparisonLines(array $extractions, array $dbscanSettings): array
{
    $lines = ['optics_vs_dbscan'];
    foreach ($extractions as $first) {
        $second = null;
        foreach ($dbscanSettings as $setting) {
            if ($setting->radius === $first->radius) {
                $second = $setting;
                break;
            }
        }
        if ($second === null) {
            continue;
        }
        $forward = $backward = [];
        foreach ($first->labels as $p => $a) {
            if (!$first->core[$p]) {
                continue;
            }
            $b = $second->labels[$p];
            $forward[$a][$b] = true;
            $backward[$b][$a] = true;
        }
        $same = count($forward) === count($first->clusters) && count($backward) === count($second->clusters);
        foreach (array_merge(array_values($forward), array_values($backward)) as $values) {
            if (count($values) !== 1) {
                $same = false;
            }
        }
        $borderNoise = $moved = 0;
        foreach ($first->labels as $p => $label) {
            if ($label === -1 && $second->labels[$p] >= 0) {
                $borderNoise++;
            }
            if ($same && $label >= 0 && !isset($forward[$label][$second->labels[$p]])) {
                $moved++;
            }
        }
        $lines[] = $first->name . ' ' . $second->name . ' core_partition ' . ($same ? 'same' : 'different') .
            ' border_as_noise ' . $borderNoise . ' moved ' . ($same ? $moved : '-');
    }
    return $lines;
}

function opticsSummary(object $ordering, int $maximum): array
{
    $sizes = [];
    foreach ($ordering->ordering as $p) {
        if ($ordering->reach[$p] === INF) {
            $sizes[] = 0;
        }
        $sizes[count($sizes) - 1]++;
    }
    $core = count(array_filter($ordering->core, fn($value) => $value !== INF));
    $singletons = count(array_filter($sizes, fn($size) => $size === 1));
    return ['optics max_eps ' . $maximum . ' core ' . $core . ' components ' . count($sizes) .
        ' singletons ' . $singletons . ' largest ' . max($sizes)];
}

function sweepLines(object $ordering, int $maximum): array
{
    $results = [];
    $lines = ['sweep max_eps ' . $maximum, 'eps clusters noise largest'];
    for ($radius = 1; $radius <= $maximum; $radius++) {
        $labels = extractOptics($ordering, $radius)->labels;
        $sizes = array_fill(0, max($labels) + 1, 0);
        $noise = 0;
        foreach ($labels as $label) {
            if ($label === -1) {
                $noise++;
            } else {
                $sizes[$label]++;
            }
        }
        $results[] = count($sizes);
        $lines[] = $radius . ' ' . count($sizes) . ' ' . $noise . ' ' . ($sizes ? max($sizes) : 0);
    }
    $stable = null;
    for ($start = 0; $start < count($results);) {
        $end = $start;
        while ($end + 1 < count($results) && $results[$end + 1] === $results[$start]) {
            $end++;
        }
        $length = $end - $start + 1;
        if ($results[$start] >= 2 && ($stable === null || $length > $stable->length)) {
            $stable = (object) ['start' => $start, 'end' => $end, 'length' => $length, 'clusters' => $results[$start]];
        }
        $start = $end + 1;
    }
    $lines[] = $stable === null ? 'stable -' : 'stable clusters ' . $stable->clusters . ' eps ' . ($stable->start + 1) .
        ' ' . ($stable->end + 1) . ' length ' . $stable->length;
    return $lines;
}

function outlierLines(object $knee, array $points, array $distances): array
{
    $core = [];
    foreach ($knee->core as $p => $value) {
        if ($value) {
            $core[] = $p;
        }
    }
    $outliers = [];
    foreach ($points as $p => $_) {
        if ($knee->labels[$p] !== -1) {
            continue;
        }
        $nearest = $core[0];
        foreach ($core as $q) {
            if (distanceAt($distances, $p, $q) < distanceAt($distances, $p, $nearest)) {
                $nearest = $q;
            }
        }
        $outliers[] = (object) ['point' => $p, 'nearest' => $nearest, 'distance' => distanceAt($distances, $p, $nearest)];
    }
    usort($outliers, fn($a, $b) => ($b->distance <=> $a->distance) ?: ($a->point <=> $b->point));
    $lines = ['outliers ' . $knee->name . ' count ' . count($outliers)];
    foreach ($outliers as $item) {
        $lines[] = $points[$item->point]->id . ' nearest_core ' . $points[$item->nearest]->id . ' cluster ' . $knee->labels[$item->nearest] .
            ' dist_sq ' . $item->distance . ' dist ' . root($item->distance);
    }
    return $lines;
}

function gapLines(object $knee, array $points, array $distances): array
{
    $lines = ['gaps ' . $knee->name];
    for ($a = 0; $a < count($knee->clusters); $a++) {
        for ($b = $a + 1; $b < count($knee->clusters); $b++) {
            $value = INF;
            foreach ($knee->clusters[$a]->members as $p) {
                foreach ($knee->clusters[$b]->members as $q) {
                    if (distanceAt($distances, $p, $q) < $value) {
                        $value = distanceAt($distances, $p, $q);
                        $first = $p;
                        $second = $q;
                    }
                }
            }
            $lines[] = $a . ' ' . $b . ' dist_sq ' . $value . ' dist ' . root($value) . ' between ' . $points[$first]->id . ' ' . $points[$second]->id;
        }
    }
    return $lines;
}

function contingencyLines(object $knee, object $xi): array
{
    $table = array_fill(0, count($knee->clusters) + 1, array_fill(0, count($xi->clusters) + 1, 0));
    foreach ($knee->labels as $p => $label) {
        $table[$label + 1][$xi->labels[$p] + 1]++;
    }
    $columns = range(-1, count($xi->clusters) - 1);
    $lines = ['contingency ' . $knee->name . ' xi', 'columns ' . implode(' ', $columns)];
    foreach ($table as $r => $row) {
        $lines[] = ($r - 1) . ' ' . implode(' ', $row);
    }
    foreach ($xi->clusters as $c => $cluster) {
        $matching = 0;
        for ($r = 1; $r < count($knee->clusters); $r++) {
            if ($table[$r + 1][$c + 1] > $table[$matching + 1][$c + 1]) {
                $matching = $r;
            }
        }
        $shared = $table[$matching + 1][$c + 1];
        $union = $knee->clusters[$matching]->size + $cluster->size - $shared;
        $lines[] = 'match ' . $c . ' ' . $matching . ' shared ' . $shared . ' jaccard ' . fraction($shared, $union);
    }
    return $lines;
}

function adjustedRand(array $first, array $second): array
{
    $pairs = $rows = $columns = [];
    foreach ($first as $p => $label) {
        $key = $label . ',' . $second[$p];
        $pairs[$key] = ($pairs[$key] ?? 0) + 1;
        $rows[$label] = ($rows[$label] ?? 0) + 1;
        $columns[$second[$p]] = ($columns[$second[$p]] ?? 0) + 1;
    }
    $combinations = fn($count) => intdiv($count * ($count - 1), 2);
    $total = fn($map) => array_sum(array_map($combinations, array_values($map)));
    $s = $total($pairs);
    $a = $total($rows);
    $b = $total($columns);
    $z = $combinations(count($first));
    $numerator = 2 * ($z * $s - $a * $b);
    $denominator = $z * ($a + $b) - 2 * $a * $b;
    return $denominator === 0 ? [1, 1] : [$numerator, $denominator];
}

function settingLines(object $setting, array $points): array
{
    $lines = ['setting ' . $setting->name . ' eps ' . $setting->radius . ' clusters ' . count($setting->clusters) .
        ' noise ' . $setting->noise . ' core ' . $setting->coreCount . ' border ' . $setting->borderCount];
    foreach ($setting->clusters as $label => $c) {
        $lines[] = 'cluster ' . $label . ' ' . character($label) . ' size ' . $c->size . ' core ' . $c->core . ' border ' . $c->border .
            ' centroid ' . fraction($c->x, $c->size) . ' ' . fraction($c->y, $c->size) . ' medoid ' . $points[$c->medoid]->id;
        $lines[] = '  bbox ' . $c->xmin . ' ' . $c->ymin . ' ' . $c->xmax . ' ' . $c->ymax .
            ' area ' . $c->area . ' density ' . fraction($c->size, $c->area);
        $lines[] = '  hull ' . count($c->hull) . ' hull_area ' . intdiv($c->twiceArea, 2) . '.' . ($c->twiceArea % 2 ? '5' : '0') .
            ' diameter_sq ' . $c->diameter . ' diameter ' . root($c->diameter);
    }
    if (isset($setting->check)) {
        $checked = $setting->check;
        $lines[] = 'check ' . implode(' ', array_map(fn($value) => $value ? 'ok' : 'fail', $checked->checks));
        $lines[] = 'isolated ' . $checked->isolated;
        $lines[] = 'ambiguous ' . count($checked->ambiguous);
        foreach ($checked->ambiguous as $item) {
            $lines[] = '  ' . $points[$item->point]->id . ' cluster ' . $setting->labels[$item->point] . ' also ' . implode(' ', $item->others);
        }
    }
    return $lines;
}

function clusterReport(array $points, object $parameters, array $grids, array $settings, array $dbscanSettings,
    array $extractions, object $ordering, object $xi, object $knee, array $distances): array
{
    $gridLines = ['grid'];
    foreach ($grids as $grid) {
        $cell = $grid->busiest;
        $gridLines[] = 'eps ' . $grid->radius . ' cells ' . $grid->cells . ' busiest ' . $cell->gx . ' ' . $cell->gy . ' ' . count($cell->points) .
            ' candidates ' . $grid->candidates . ' pairs ' . $grid->pairs . ' brute_pairs ' . $grid->brutePairs . ' ' . ($grid->matches ? 'ok' : 'mismatch');
        $occupancy = $grid->occupancy;
        ksort($occupancy, SORT_NUMERIC);
        $entries = [];
        foreach ($occupancy as $count => $number) {
            $entries[] = $count . ':' . $number;
        }
        $gridLines[] = '  occupancy ' . implode(' ', $entries);
    }
    $xiLines = ['xi ' . $parameters->xiText . ' min_size ' . $parameters->minimumSize . ' steep_areas ' . count($xi->steepAreas)];
    foreach ($xi->steepAreas as $area) {
        $xiLines[] = $area->direction . ' ' . $area->start . ' ' . $area->end;
    }
    $xiLines[] = 'xi_clusters ' . count($xi->clusters);
    foreach ($xi->clusters as $j => $cluster) {
        $xiLines[] = $j . ' start ' . $cluster->start . ' end ' . $cluster->end . ' size ' . $cluster->size .
            ' label ' . ($cluster->label ?? '-') . ' parent ' . ($cluster->parent ?? '-') .
            ' walls ' . root($cluster->left) . ' ' . root($cluster->right) . ' valley ' . root($cluster->valley);
    }
    $ariLines = ['ari'];
    for ($a = 0; $a < count($settings); $a++) {
        for ($b = $a + 1; $b < count($settings); $b++) {
            [$numerator, $denominator] = adjustedRand($settings[$a]->labels, $settings[$b]->labels);
            $ariLines[] = $settings[$a]->name . ' ' . $settings[$b]->name . ' ' . fraction($numerator, $denominator) . ' ' . ariValue($numerator, $denominator);
        }
    }
    $parts = [['points ' . count($points) . ' min_pts ' . $parameters->minimum,
        'settings ' . implode(' ', array_map(fn($setting) => $setting->name, $settings))], $gridLines];
    foreach ($settings as $setting) {
        $parts[] = settingLines($setting, $points);
    }
    array_push($parts, containmentLines($dbscanSettings), comparisonLines($extractions, $dbscanSettings),
        opticsSummary($ordering, $parameters->maximum), sweepLines($ordering, $parameters->maximum), $xiLines,
        outlierLines($knee, $points, $distances), gapLines($knee, $points, $distances),
        contingencyLines($knee, $settings[count($settings) - 1]), $ariLines);
    $lines = [];
    foreach ($parts as $index => $part) {
        if ($index > 0) {
            $lines[] = '';
        }
        array_push($lines, ...$part);
    }
    return $lines;
}

function kdistReport(array $points, array $curves, object $kdist, array $dbscanSettings, object $ordering, object $parameters): array
{
    $lines = ['k_distance k ' . ($parameters->minimum - 1) . ' points ' . count($points), 'rank id kdist_sq kdist'];
    foreach ($kdist->order as $i => $p) {
        $lines[] = ($i + 1) . ' ' . $points[$p]->id . ' ' . $kdist->values[$p] . ' ' . root($kdist->values[$p]);
    }
    $p = $kdist->order[$kdist->knee];
    array_push($lines, '', 'knee rank ' . ($kdist->knee + 1) . ' id ' . $points[$p]->id . ' kdist_sq ' . $kdist->values[$p] .
        ' kdist ' . root($kdist->values[$p]) . ' cross ' . $kdist->cross, 'suggested_eps ' . $kdist->radius, '', 'knee_table');
    foreach ($curves as $curve) {
        $point = $curve->order[$curve->knee];
        $lines[] = 'k ' . $curve->j . ' rank ' . ($curve->knee + 1) . ' id ' . $points[$point]->id .
            ' kdist_sq ' . $curve->values[$point] . ' eps ' . $curve->radius;
    }
    array_push($lines, '', 'core_check');
    foreach ($dbscanSettings as $setting) {
        $count = count(array_filter($kdist->values, fn($value) => $value <= $setting->radius * $setting->radius));
        $gridCore = count(array_filter($setting->core));
        $lines[] = 'eps ' . $setting->radius . ' core ' . $count . ' non_core ' . (count($points) - $count) .
            ' grid_core ' . $gridCore . ' ' . ($count === $gridCore ? 'ok' : 'mismatch');
    }
    $core = count(array_filter($ordering->core, fn($value) => $value !== INF));
    $match = true;
    foreach ($ordering->core as $point => $value) {
        if ($value !== INF && $value !== $kdist->values[$point]) {
            $match = false;
        }
    }
    $lines[] = 'optics max_eps ' . $parameters->maximum . ' core ' . $core . ' ' . ($match ? 'ok' : 'mismatch');
    return $lines;
}

function mapCells(array $points, int $width, int $height): array
{
    $xmin = min(array_map(fn($point) => $point->x, $points));
    $xmax = max(array_map(fn($point) => $point->x, $points));
    $ymin = min(array_map(fn($point) => $point->y, $points));
    $ymax = max(array_map(fn($point) => $point->y, $points));
    $rows = array_fill(0, $height, array_fill(0, $width, []));
    foreach ($points as $p => $point) {
        $column = intdiv(($point->x - $xmin) * $width, $xmax - $xmin + 1);
        $row = intdiv(($ymax - $point->y) * $height, $ymax - $ymin + 1);
        $rows[$row][$column][] = $p;
    }
    return $rows;
}

function mapReport(array $points, object $parameters, array $settings, object $knee, array $extractions, object $ordering, object $kdist): array
{
    $cells = mapCells($points, ...$parameters->mapSize);
    $lines = [];
    foreach ($settings as $setting) {
        $rows = [];
        foreach ($cells as $row) {
            $text = '';
            foreach ($row as $cell) {
                if (!$cell) {
                    $text .= ' ';
                    continue;
                }
                $labels = [];
                foreach ($cell as $p) {
                    if ($setting->labels[$p] >= 0) {
                        $labels[$setting->labels[$p]] = true;
                    }
                }
                $text .= !$labels ? '.' : (count($labels) === 1 ? character(array_key_first($labels)) : '*');
            }
            $rows[] = $text;
        }
        $lines[] = 'map ' . $setting->name . ' clusters ' . count($setting->clusters) . ' noise ' . $setting->noise;
        array_push($lines, ...frame($rows));
        $legend = [];
        foreach ($setting->clusters as $label => $cluster) {
            $legend[] = character($label) . '=' . $cluster->size;
        }
        $lines[] = 'legend ' . ($legend ? implode(' ', $legend) : '-');
        $lines[] = '';
    }
    $kinds = [];
    foreach ($cells as $row) {
        $text = '';
        foreach ($row as $cell) {
            $core = $border = false;
            foreach ($cell as $p) {
                $core = $core || $knee->core[$p];
                $border = $border || $knee->labels[$p] >= 0;
            }
            $text .= $core ? '#' : ($border ? '+' : ($cell ? '.' : ' '));
        }
        $kinds[] = $text;
    }
    $lines[] = 'kinds ' . $knee->name;
    array_push($lines, ...frame($kinds));
    $lines[] = '';
    [$width, $height] = $parameters->kdistSize;
    $maximum = $kdist->values[$kdist->order[0]];
    $heights = [];
    $kneeColumn = 0;
    for ($c = 0; $c < $width; $c++) {
        $first = intdiv($c * count($points), $width);
        $end = intdiv(($c + 1) * count($points), $width);
        if ($first <= $kdist->knee && $kdist->knee < $end) {
            $kneeColumn = $c;
        }
        $value = $kdist->values[$kdist->order[$first]];
        $h = 0;
        while ($h < $height && ($h + 1) * ($h + 1) * $maximum <= $height * $height * $value) {
            $h++;
        }
        $heights[] = $h;
    }
    $plot = [];
    for ($row = 0; $row < $height; $row++) {
        $text = '';
        foreach ($heights as $c => $h) {
            $text .= $height - $row <= $h ? '#' : ($c === $kneeColumn ? ':' : ' ');
        }
        $plot[] = $text;
    }
    $lines[] = 'kdist_plot k ' . ($parameters->minimum - 1) . ' max ' . root($maximum) . ' knee_column ' . ($kneeColumn + 1);
    array_push($lines, ...frame($plot));
    $lines[] = '';
    $finite = array_values(array_filter($ordering->reach, fn($value) => $value !== INF));
    $top = max($finite);
    $columns = array_merge($extractions, [$settings[count($settings) - 1]]);
    $lines[] = 'reachability width ' . $parameters->reachWidth . ' max_reach ' . root($top) .
        ' columns ' . implode(' ', array_map(fn($setting) => $setting->name, $columns));
    foreach ($ordering->ordering as $i => $p) {
        $reach = $ordering->reach[$p];
        if ($reach === INF) {
            $bar = str_repeat('-', $parameters->reachWidth);
        } else {
            $length = 0;
            while ($length < $parameters->reachWidth && ($length + 1) * ($length + 1) * $top <=
                $parameters->reachWidth * $parameters->reachWidth * $reach) {
                $length++;
            }
            $bar = str_repeat('#', $length);
        }
        $chars = implode('', array_map(fn($setting) => character($setting->labels[$p]), $columns));
        $lines[] = str_pad((string) ($i + 1), 4, ' ', STR_PAD_LEFT) . ' ' . str_pad((string) $points[$p]->id, 5, ' ', STR_PAD_LEFT) .
            ' ' . str_pad(root($reach), 7, ' ', STR_PAD_LEFT) . ' ' . $chars . ' |' . $bar;
    }
    return $lines;
}

$data = readDataset();
$points = $data->points;
$parameters = $data->parameters;
$distances = distanceMatrix($points);
$curves = kneeCurves($distances, $parameters->minimum);
$kdist = $curves->kdist;
$radii = array_values(array_unique(array_merge($parameters->eps, [$kdist->radius, $parameters->maximum])));
sort($radii, SORT_NUMERIC);
$dbscanSettings = [];
foreach ($parameters->eps as $radius) {
    $dbscanSettings[] = (object) ['name' => 'db' . $radius, 'radius' => $radius];
}
$dbscanSettings[] = (object) ['name' => 'knee' . $kdist->radius, 'radius' => $kdist->radius];
$grids = [];
$ordering = null;
foreach ($radii as $radius) {
    $grid = buildGrid($points, $radius, $distances);
    foreach ($dbscanSettings as $setting) {
        if ($setting->radius !== $radius) {
            continue;
        }
        $result = dbscan($grid->neighborhoods, $parameters->minimum);
        $setting->labels = $result->labels;
        $setting->core = $result->core;
        $setting->check = checkDbscan($setting, $grid->neighborhoods);
        summarize($setting, $points, $distances);
    }
    if ($radius === $parameters->maximum) {
        $ordering = optics($grid->neighborhoods, $parameters->minimum, $distances);
    }
    unset($grid->neighborhoods, $grid->candidateCounts);
    $grids[$radius] = $grid;
}
$extractions = [];
foreach ($parameters->extracts as $radius) {
    $result = extractOptics($ordering, $radius);
    $setting = (object) ['name' => 'op' . $radius, 'radius' => $radius, 'labels' => $result->labels, 'core' => $result->core];
    $extractions[] = summarize($setting, $points, $distances);
}
$xi = xiExtraction($ordering, $parameters);
$xiSetting = summarize((object) ['name' => 'xi', 'radius' => $parameters->maximum, 'labels' => $xi->labels, 'core' => $xi->core], $points, $distances);
$settings = array_merge($dbscanSettings, $extractions, [$xiSetting]);
$knee = $dbscanSettings[count($dbscanSettings) - 1];
$labels = ['id,' . implode(',', array_map(fn($setting) => $setting->name, $settings))];
foreach ($points as $p => $point) {
    $values = array_map(fn($setting) => $setting->labels[$p], $settings);
    $labels[] = implode(',', array_merge([$point->id], $values));
}
$opticsRows = ['order,id,core_sq,reach_sq,reach,predecessor'];
foreach ($ordering->ordering as $i => $p) {
    $opticsRows[] = implode(',', [$i + 1, $points[$p]->id, formatInteger($ordering->core[$p]), formatInteger($ordering->reach[$p]),
        root($ordering->reach[$p]), $ordering->predecessor[$p] < 0 ? '-' : $points[$ordering->predecessor[$p]]->id]);
}
writeLines('labels.csv', $labels);
writeLines('optics_order.csv', $opticsRows);
writeLines('kdist.txt', kdistReport($points, $curves->curves, $kdist, $dbscanSettings, $ordering, $parameters));
writeLines('clusters.txt', clusterReport($points, $parameters, $grids, $settings, $dbscanSettings, $extractions, $ordering, $xi, $knee, $distances));
writeLines('maps.txt', mapReport($points, $parameters, $settings, $knee, $extractions, $ordering, $kdist));
