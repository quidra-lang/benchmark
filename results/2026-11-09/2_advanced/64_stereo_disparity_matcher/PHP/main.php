<?php

require_once __DIR__ . '/pgm_io.php';
require_once __DIR__ . '/costs.php';
require_once __DIR__ . '/aggregation.php';
require_once __DIR__ . '/refinement.php';
require_once __DIR__ . '/evaluation.php';

const METHODS = ['sad', 'ssd', 'census', 'sgm', 'fusion', 'wta_final', 'sgm_final'];
const SELECTION_METHODS = ['sad', 'ssd', 'census', 'sgm'];
const REASONS = ['textureless' => 50, 'nonunique' => 100, 'outside' => 150, 'mismatch' => 200, 'occluded' => 255];
const SOURCES = ['kept', 'median', 'background', 'interpolated', 'none'];

function lowerMedian(array $values): int
{
    sort($values, SORT_NUMERIC);
    return $values[intdiv(count($values) - 1, 2)];
}

function validCount(array $image): int
{
    return count(array_filter($image, fn($value) => $value !== 0));
}

function frequencies(array $values): array
{
    $counts = [];
    foreach ($values as $value) $counts[$value] = ($counts[$value] ?? 0) + 1;
    return $counts;
}

function makeCosts(array $data, string $kind, int $window): array
{
    return costVolume($data['left'], $data['right'], $data['censusLeft'], $data['censusRight'], $data['width'], $data['height'],
        $kind, $window, $data['params']['disparity_min'], $data['params']['disparity_max']);
}

function selectDisparities(array $volume, array $data): array
{
    $width = $data['width'];
    $height = $data['height'];
    $params = $data['params'];
    $minimum = $params['disparity_min'];
    $maximum = $params['disparity_max'];
    $right = array_fill(0, count($volume), null);
    for ($y = 0; $y < $height; $y++) {
        for ($x = 0; $x < $width; $x++) {
            $p = $y * $width + $x;
            for ($d = $minimum; $d <= $maximum && $x + $d < $width; $d++) {
                $chosen = $right[$p];
                if ($chosen === null || $volume[$p + $d][$d - $minimum] < $volume[$p + $chosen][$chosen - $minimum]) $right[$p] = $d;
            }
        }
    }
    $image = $reasons = $margins = array_fill(0, count($volume), 0);
    $lr = [0, 0, 0, 0];
    $bounds = 0;
    foreach ($volume as $p => $costs) {
        $x = $p % $width;
        $best = $minimum;
        for ($d = $minimum + 1; $d <= $maximum; $d++) if ($costs[$d - $minimum] < $costs[$best - $minimum]) $best = $d;
        $first = $costs[$best - $minimum];
        $second = PHP_INT_MAX;
        for ($d = $minimum; $d <= $maximum; $d++) {
            if (abs($d - $best) >= 2) $second = min($second, $costs[$d - $minimum]);
        }
        $consistent = fn($d) => $x >= $d && abs($d - $right[$p - $d]) <= $params['lr_max_diff'];
        if ($best === $minimum || $best === $maximum) $bounds++;
        $reason = 0;
        if ($data['strengths'][$p] < $params['texture_threshold']) $reason = 50;
        elseif (100 * $second <= (100 + $params['uniqueness']) * $first) $reason = 100;
        elseif ($x < $best) $reason = 150;
        elseif (!$consistent($best)) {
            $reason = 255;
            for ($d = $minimum; $d <= $maximum; $d++) {
                if ($consistent($d)) {
                    $reason = 200;
                    break;
                }
            }
        } else {
            $image[$p] = $best;
            $margins[$p] = $second - $first;
        }
        $reasons[$p] = $reason;
        if ($reason === 0 || $reason === 200 || $reason === 255) $lr[min(3, abs($best - $right[$p - $best]))]++;
    }
    return compact('image', 'reasons', 'margins', 'lr', 'bounds');
}

function chooseWindows(array $data): array
{
    $methods = $sweeps = [];
    foreach (['sad', 'ssd', 'census'] as $kind) {
        $bestMetrics = null;
        foreach ($data['params'][$kind . '_windows'] as $window) {
            $selected = selectDisparities(makeCosts($data, $kind, $window), $data);
            $selected['window'] = $window;
            $metrics = evaluate($selected['image'], $data['truth'], $data['regions']['nonocc']);
            $sweeps[] = compact('kind', 'window', 'metrics') + ['valid' => validCount($selected['image'])];
            if ($bestMetrics === null || $metrics['bad1'] < $bestMetrics['bad1'] ||
                ($metrics['bad1'] === $bestMetrics['bad1'] && $metrics['bad2'] < $bestMetrics['bad2'])) {
                $bestMetrics = $metrics;
                $methods[$kind] = $selected;
            }
        }
    }
    return compact('methods', 'sweeps');
}

function semiGlobal(array $data): array
{
    $params = $data['params'];
    $base = makeCosts($data, $params['sgm_cost'], $params['sgm_window']);
    $progress = [];
    $selected = $summedCosts = null;
    foreach (cumulativeCosts($base, $data['left'], $data['width'], $data['height'], $params['sgm_paths'], $params['p1'], $params['p2'], $params['p2_gamma']) as $total) {
        $selected = selectDisparities($total, $data);
        $progress[] = ['number' => count($progress) + 1, 'metrics' => evaluate($selected['image'], $data['truth'], $data['regions']['nonocc']),
            'valid' => validCount($selected['image'])];
        $summedCosts = $total;
    }
    $selected['window'] = $params['sgm_window'];
    return compact('selected', 'summedCosts', 'progress');
}

function neighbors4(int $p, array $data): array
{
    $x = $p % $data['width'];
    $y = intdiv($p, $data['width']);
    $result = [];
    foreach ([[$x + 1, $y], [$x - 1, $y], [$x, $y + 1], [$x, $y - 1]] as [$xx, $yy]) {
        if ($xx >= 0 && $xx < $data['width'] && $yy >= 0 && $yy < $data['height']) $result[] = $yy * $data['width'] + $xx;
    }
    return $result;
}

function connectedRegions(array $image, array $data, int $maximumDifference): array
{
    $seen = array_fill(0, count($image), false);
    $components = [];
    foreach ($image as $start => $value) {
        if ($value === 0 || $seen[$start]) continue;
        $seen[$start] = true;
        $stack = [$start];
        $component = [];
        while ($stack) {
            $p = array_pop($stack);
            $component[] = $p;
            foreach (neighbors4($p, $data) as $q) {
                if ($image[$q] !== 0 && !$seen[$q] && abs($image[$q] - $image[$p]) <= $maximumDifference) {
                    $seen[$q] = true;
                    $stack[] = $q;
                }
            }
        }
        $components[] = $component;
    }
    return $components;
}

function medianFilter(array $image, array $data): array
{
    $result = [];
    foreach ($image as $p => $value) {
        if ($value === 0) {
            $result[] = 0;
            continue;
        }
        $x = $p % $data['width'];
        $y = intdiv($p, $data['width']);
        $values = [];
        for ($yy = max(0, $y - 1); $yy <= min($data['height'] - 1, $y + 1); $yy++) {
            for ($xx = max(0, $x - 1); $xx <= min($data['width'] - 1, $x + 1); $xx++) {
                $v = $image[$yy * $data['width'] + $xx];
                if ($v !== 0) $values[] = $v;
            }
        }
        $result[] = lowerMedian($values);
    }
    return $result;
}

function rayValues(array $image, array $data, int $p, array $directions): array
{
    $values = [];
    $x = $p % $data['width'];
    $y = intdiv($p, $data['width']);
    foreach ($directions as [$dx, $dy]) {
        for ($xx = $x + $dx, $yy = $y + $dy; $xx >= 0 && $xx < $data['width'] && $yy >= 0 && $yy < $data['height']; $xx += $dx, $yy += $dy) {
            $value = $image[$yy * $data['width'] + $xx];
            if ($value !== 0) {
                $values[] = $value;
                break;
            }
        }
    }
    return $values;
}

function postprocess(array $selection, array $data): array
{
    $original = $selection['image'];
    $params = $data['params'];
    $filtered = $original;
    $speckles = $specklePixels = 0;
    foreach (connectedRegions($original, $data, $params['speckle_range']) as $component) {
        if (count($component) >= $params['speckle_size']) continue;
        $speckles++;
        $specklePixels += count($component);
        foreach ($component as $p) $filtered[$p] = 0;
    }
    $medians = medianFilter($filtered, $data);
    $image = $medians;
    $sources = array_fill(0, count($image), 'none');
    $medianChanged = 0;
    foreach ($image as $p => $value) {
        if ($filtered[$p] !== $medians[$p]) $medianChanged++;
        if ($medians[$p] !== 0) {
            $sources[$p] = $medians[$p] === $original[$p] ? 'kept' : 'median';
        } elseif ($selection['reasons'][$p] === 150 || $selection['reasons'][$p] === 255) {
            $values = rayValues($medians, $data, $p, [[-1, 0], [1, 0]]);
            if ($values) {
                $image[$p] = min($values);
                $sources[$p] = 'background';
            }
        } else {
            $values = rayValues($medians, $data, $p, DIRECTIONS);
            if ($values) {
                $image[$p] = lowerMedian($values);
                $sources[$p] = 'interpolated';
            }
        }
    }
    $counts = frequencies($sources);
    return compact('image', 'sources', 'speckles', 'specklePixels', 'medianChanged') +
        ['background' => $counts['background'] ?? 0, 'interpolated' => $counts['interpolated'] ?? 0, 'unfilled' => $counts['none'] ?? 0];
}

function fuse(array $methods, int $minimumVotes): array
{
    $votes = [0, 0, 0, 0, 0];
    $image = [];
    foreach ($methods['sad']['image'] as $p => $_) {
        $values = [];
        foreach (SELECTION_METHODS as $name) if ($methods[$name]['image'][$p] !== 0) $values[] = $methods[$name]['image'][$p];
        $votes[count($values)]++;
        if (!$values) {
            $image[] = 0;
            continue;
        }
        $median = lowerMedian($values);
        $agree = 0;
        foreach ($values as $value) if (abs($value - $median) <= 1) $agree++;
        $image[] = $agree >= $minimumVotes ? $median : 0;
    }
    return compact('image', 'votes');
}

function extractObjects(array $image, array $data): array
{
    $width = $data['width'];
    $truth = $data['truth'];
    $params = $data['params'];
    $counts = frequencies(array_values(array_filter($truth, fn($value) => $value !== 0)));
    $objects = [];
    $small = 0;
    foreach (connectedRegions($image, $data, $params['object_range']) as $component) {
        if (count($component) < $params['object_min_size']) {
            $small++;
            continue;
        }
        $n = count($component);
        $xs = $ys = $values = $truthValues = [];
        foreach ($component as $p) {
            $xs[] = $p % $width;
            $ys[] = intdiv($p, $width);
            $values[] = $image[$p];
            if ($truth[$p] !== 0) $truthValues[] = $truth[$p];
        }
        $box = [min($xs), min($ys), max($xs), max($ys)];
        $median = lowerMedian($values);
        $total = array_sum($values);
        $layerCounts = frequencies($truthValues);
        $candidates = array_keys($layerCounts);
        usort($candidates, fn($a, $b) => ($layerCounts[$b] <=> $layerCounts[$a]) ?: ($a <=> $b));
        $layer = $candidates[0] ?? null;
        $hits = $layer === null ? 0 : $layerCounts[$layer];
        $objects[] = ['pixels' => $n, 'box' => $box, 'minimum' => min($values), 'maximum' => max($values), 'median' => $median,
            'mean' => twoDecimals($total, $n), 'depth' => twoDecimals($params['focal_length'] * $params['baseline'] * $n, $total),
            'width' => twoDecimals(($box[2] - $box[0] + 1) * $params['baseline'], $median),
            'height' => twoDecimals(($box[3] - $box[1] + 1) * $params['baseline'], $median),
            'truth' => $layer, 'hits' => $hits, 'union' => $layer === null ? 0 : $n + $counts[$layer] - $hits, 'first' => min($component)];
    }
    usort($objects, fn($a, $b) => ($b['median'] <=> $a['median']) ?: ($b['pixels'] <=> $a['pixels']) ?: ($a['first'] <=> $b['first']));
    $detected = [];
    foreach ($objects as $item) if ($item['truth'] !== null && 2 * $item['hits'] > $item['union']) $detected[$item['truth']] = true;
    $layers = array_keys($counts);
    sort($layers, SORT_NUMERIC);
    return compact('objects', 'small', 'layers', 'detected');
}

function objectLines(array $result): array
{
    $total = 0;
    foreach ($result['objects'] as $object) $total += $object['pixels'];
    $lines = ['objects ' . count($result['objects']) . ' small ' . $result['small'] . ' pixels ' . $total];
    foreach ($result['objects'] as $i => $item) {
        $truth = $item['truth'] === null ? 'truth - iou -' : 'truth ' . $item['truth'] . ' iou ' . ratio($item['hits'], $item['union']);
        $lines[] = 'object ' . ($i + 1) . ' pixels ' . $item['pixels'] . ' box ' . implode(' ', $item['box']) .
            ' disparity ' . $item['minimum'] . ' ' . $item['maximum'] . ' median ' . $item['median'] . ' mean ' . $item['mean'] .
            ' depth ' . $item['depth'] . ' size ' . $item['width'] . ' ' . $item['height'] . ' ' . $truth;
    }
    $missed = [];
    foreach ($result['layers'] as $layer) if (!isset($result['detected'][$layer])) $missed[] = $layer;
    $lines[] = 'layers ' . count($result['layers']) . ' detected ' . count($result['detected']) . ' missed ' . ($missed ? implode(' ', $missed) : '-');
    return $lines;
}

function sampleLines(array $methods, array $summedCosts, array $data): array
{
    $params = $data['params'];
    $focal = $params['focal_length'];
    $baseline = $params['baseline'];
    $lines = ['x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth'];
    foreach ($params['samplePixels'] as [$x, $y]) {
        $p = $y * $data['width'] + $x;
        $values = [$x, $y];
        foreach (SELECTION_METHODS as $name) $values[] = $methods[$name]['image'][$p] ?: '-';
        $disparity = $methods['sgm_final']['image'][$p];
        if ($disparity !== 0) {
            [$refined, $depth] = subpixel($disparity, $summedCosts[$p], $params['disparity_min'], $params['disparity_max'], $focal, $baseline);
            array_push($values, $disparity, $methods['sgm_final']['sources'][$p], $refined, $depth);
        } else {
            array_push($values, '-', 'none', '-', '-');
        }
        if ($data['truth'][$p] !== 0) {
            $values[] = $data['truth'][$p];
            $values[] = twoDecimals($focal * $baseline, $data['truth'][$p]);
        } else {
            array_push($values, '-', '-');
        }
        $lines[] = implode(',', $values);
    }
    return $lines;
}

function inputSummary(array $data): array
{
    $size = $data['width'] * $data['height'];
    $left = $data['left'];
    $right = $data['right'];
    $regions = $data['regions'];
    $params = $data['params'];
    $absolute = $biasSum = 0;
    foreach ($regions['nonocc'] as $p) {
        $delta = $right[$p - $data['truth'][$p]] - $left[$p];
        $absolute += abs($delta);
        $biasSum += $delta;
    }
    $bias = twoDecimals(abs($biasSum), count($regions['nonocc']));
    if ($biasSum < 0 && $bias !== '0.00') $bias = '-' . $bias;
    return ['image ' . $data['width'] . ' ' . $data['height'],
        'disparities ' . $params['disparity_min'] . ' ' . $params['disparity_max'],
        'left mean ' . twoDecimals(array_sum($left), $size) . ' min ' . min($left) . ' max ' . max($left),
        'right mean ' . twoDecimals(array_sum($right), $size) . ' min ' . min($right) . ' max ' . max($right),
        'texture mean ' . twoDecimals(array_sum($data['strengths']), $size) . ' textureless ' .
            count(array_filter($data['strengths'], fn($value) => $value < $params['texture_threshold'])),
        'ground_truth known ' . count($regions['all']) . ' nonocc ' . count($regions['nonocc']) . ' occluded ' . count($regions['occluded']) .
            ' disc ' . count($regions['disc']) . ' unknown ' . ($size - count($regions['all'])),
        'photometric pixels ' . count($regions['nonocc']) . ' mean_abs ' . twoDecimals($absolute, count($regions['nonocc'])) . ' bias ' . $bias];
}

function sweepLines(array $sweeps, array $progress): array
{
    $lines = [];
    foreach ($sweeps as $item) {
        $metrics = $item['metrics'];
        $lines[] = 'sweep ' . $item['kind'] . ' window ' . $item['window'] . ' valid ' . $item['valid'] .
            ' bad1 ' . ratio($metrics['bad1'], $metrics['pixels']) . ' bad2 ' . ratio($metrics['bad2'], $metrics['pixels']);
    }
    foreach ($progress as $item) {
        $metrics = $item['metrics'];
        $lines[] = 'paths ' . $item['number'] . ' valid ' . $item['valid'] . ' bad1 ' . ratio($metrics['bad1'], $metrics['pixels']) .
            ' bad2 ' . ratio($metrics['bad2'], $metrics['pixels']);
    }
    return $lines;
}

function disparitySummary(string $name, array $image, array $data): array
{
    $values = array_values(array_filter($image, fn($d) => $d !== 0));
    $horizontal = $vertical = 0;
    foreach ($image as $p => $value) {
        if ($value === 0) continue;
        if ($p % $data['width'] + 1 < $data['width'] && $image[$p + 1] !== 0 && abs($value - $image[$p + 1]) >= 2) $horizontal++;
        if ($p + $data['width'] < count($image) && $image[$p + $data['width']] !== 0 && abs($value - $image[$p + $data['width']]) >= 2) $vertical++;
    }
    $distribution = $values ? 'disparity min ' . min($values) . ' max ' . max($values) . ' median ' . lowerMedian($values) .
        ' distinct ' . count(array_unique($values)) : 'disparity min - max - median - distinct 0';
    return ['method ' . $name . ' valid ' . count($values) . ' invalid ' . (count($image) - count($values)), $distribution,
        'jumps horizontal ' . $horizontal . ' vertical ' . $vertical];
}

function selectionDetails(array $method): array
{
    $counts = frequencies($method['reasons']);
    $parts = [];
    foreach (REASONS as $name => $code) $parts[] = $name . ' ' . ($counts[$code] ?? 0);
    return ['window ' . $method['window'] . ' bounds ' . $method['bounds'], 'reasons ' . implode(' ', $parts),
        'lr 0 ' . $method['lr'][0] . ' 1 ' . $method['lr'][1] . ' 2 ' . $method['lr'][2] . ' 3+ ' . $method['lr'][3]];
}

function postprocessDetails(array $method, array $data): array
{
    $lines = ['postprocess speckles ' . $method['speckles'] . ' ' . $method['specklePixels'] . ' median ' . $method['medianChanged'] .
        ' background ' . $method['background'] . ' interpolated ' . $method['interpolated'] . ' unfilled ' . $method['unfilled']];
    foreach (SOURCES as $source) {
        $region = [];
        foreach ($data['regions']['all'] as $p) if ($method['sources'][$p] === $source) $region[] = $p;
        $metrics = evaluate($method['image'], $data['truth'], $region);
        $lines[] = 'source ' . $source . ' pixels ' . $metrics['pixels'] . ' bad1 ' . ratio($metrics['bad1'], $metrics['pixels']);
    }
    return $lines;
}

function regionLine(string $region, array $metrics): string
{
    return 'region ' . $region . ' pixels ' . $metrics['pixels'] . ' valid ' . $metrics['valid'] .
        ' bad1 ' . ratio($metrics['bad1'], $metrics['pixels']) . ' bad2 ' . ratio($metrics['bad2'], $metrics['pixels']) .
        ' mae ' . $metrics['mae'] . ' exact ' . $metrics['exact'];
}

function depthErrorLine(array $image, array $data): string
{
    $errors = [];
    foreach ($data['regions']['nonocc'] as $p) {
        if ($image[$p] === 0) continue;
        $errors[] = abs(depthHundredths($image[$p], $data['params']['focal_length'], $data['params']['baseline']) -
            depthHundredths($data['truth'][$p], $data['params']['focal_length'], $data['params']['baseline']));
    }
    return $errors ? 'depth_error pixels ' . count($errors) . ' mean ' . twoDecimals(array_sum($errors), 100 * count($errors)) .
        ' max ' . twoDecimals(max($errors), 100) : 'depth_error pixels 0 mean - max -';
}

function errorCountsLine(array $image, array $data): string
{
    $errors = [0, 0, 0, 0, 0];
    $invalid = 0;
    foreach ($data['regions']['all'] as $p) {
        if ($image[$p] === 0) $invalid++;
        else $errors[min(4, abs($image[$p] - $data['truth'][$p]))]++;
    }
    return 'errors 0 ' . $errors[0] . ' 1 ' . $errors[1] . ' 2 ' . $errors[2] . ' 3 ' . $errors[3] .
        ' 4+ ' . $errors[4] . ' invalid ' . $invalid;
}

function methodLines(string $name, array $method, array $metrics, array $data): array
{
    $lines = disparitySummary($name, $method['image'], $data);
    if (in_array($name, SELECTION_METHODS, true)) {
        $lines = array_merge($lines, selectionDetails($method));
    } elseif ($name === 'fusion') {
        $parts = [];
        foreach ($method['votes'] as $n => $count) $parts[] = $n . ' ' . $count;
        $lines[] = 'votes ' . implode(' ', $parts);
    } else {
        $lines = array_merge($lines, postprocessDetails($method, $data));
    }
    foreach (REGION_ORDER as $region) $lines[] = regionLine($region, $metrics[$name][$region]);
    $lines[] = depthErrorLine($method['image'], $data);
    $lines[] = errorCountsLine($method['image'], $data);
    return $lines;
}

function rankingLines(array $metrics): array
{
    $lines = [];
    foreach (REGION_ORDER as $region) {
        $names = METHODS;
        usort($names, function ($a, $b) use ($region, $metrics) {
            $x = $metrics[$a][$region];
            $y = $metrics[$b][$region];
            $comparison = ($x['bad1'] <=> $y['bad1']) ?: ($x['bad2'] <=> $y['bad2']);
            if ($comparison !== 0) return $comparison;
            if ($x['valid'] === 0 || $y['valid'] === 0) $comparison = ($x['valid'] === 0 ? 1 : 0) <=> ($y['valid'] === 0 ? 1 : 0);
            else $comparison = ($x['errorSum'] * $y['valid']) <=> ($y['errorSum'] * $x['valid']);
            return $comparison ?: (array_search($a, METHODS, true) <=> array_search($b, METHODS, true));
        });
        $lines[] = 'ranking ' . $region . ' ' . implode(' ', $names);
    }
    return $lines;
}

function occlusionLines(array $methods, array $regions): array
{
    $lines = [];
    foreach (SELECTION_METHODS as $name) {
        $tp = $fp = 0;
        foreach ($regions['occluded'] as $p) if ($methods[$name]['reasons'][$p] === 150 || $methods[$name]['reasons'][$p] === 255) $tp++;
        foreach ($regions['nonocc'] as $p) if ($methods[$name]['reasons'][$p] === 150 || $methods[$name]['reasons'][$p] === 255) $fp++;
        $fn = count($regions['occluded']) - $tp;
        $lines[] = 'occlusion ' . $name . ' tp ' . $tp . ' fp ' . $fp . ' fn ' . $fn .
            ' precision ' . ratio($tp, $tp + $fp) . ' recall ' . ratio($tp, $tp + $fn);
    }
    return $lines;
}

function confidenceLines(array $methods, array $data): array
{
    $lines = [];
    foreach (SELECTION_METHODS as $name) {
        $method = $methods[$name];
        $pixels = [];
        foreach ($data['regions']['nonocc'] as $p) if ($method['image'][$p] !== 0) $pixels[] = $p;
        usort($pixels, fn($a, $b) => ($method['margins'][$b] <=> $method['margins'][$a]) ?: ($a <=> $b));
        foreach ([25, 50, 75, 100] as $percentage) {
            $count = intdiv(count($pixels) * $percentage + 99, 100);
            $bad = 0;
            for ($i = 0; $i < $count; $i++) {
                $p = $pixels[$i];
                if (abs($method['image'][$p] - $data['truth'][$p]) > 1) $bad++;
            }
            $margin = $count === 0 ? '-' : $method['margins'][$pixels[$count - 1]];
            $lines[] = 'confidence ' . $name . ' ' . $percentage . ' pixels ' . $count . ' margin ' . $margin . ' bad1 ' . ratio($bad, $count);
        }
    }
    return $lines;
}

function layerLines(array $methods, array $data): array
{
    $counts = frequencies(array_values(array_filter($data['truth'], fn($value) => $value !== 0)));
    $layers = array_keys($counts);
    sort($layers, SORT_NUMERIC);
    $lines = [];
    foreach ($layers as $layer) {
        $nonocc = [];
        foreach ($data['regions']['nonocc'] as $p) if ($data['truth'][$p] === $layer) $nonocc[] = $p;
        $errors = [];
        foreach (METHODS as $name) $errors[] = evaluate($methods[$name]['image'], $data['truth'], $nonocc)['bad1'];
        $lines[] = 'layer ' . $layer . ' pixels ' . $counts[$layer] . ' nonocc ' . count($nonocc) . ' bad1 ' . implode(' ', $errors);
    }
    return $lines;
}

function evaluationLines(array $methods, array $sweeps, array $progress, array $data): array
{
    $metrics = [];
    foreach (METHODS as $name) {
        foreach (REGION_ORDER as $region) $metrics[$name][$region] = evaluate($methods[$name]['image'], $data['truth'], $data['regions'][$region]);
    }
    $lines = array_merge(inputSummary($data), sweepLines($sweeps, $progress));
    foreach (METHODS as $name) $lines = array_merge($lines, methodLines($name, $methods[$name], $metrics, $data));
    $lines = array_merge($lines, rankingLines($metrics), occlusionLines($methods, $data['regions']), confidenceLines($methods, $data), layerLines($methods, $data));
    $counts = frequencies($methods['sgm_final']['image']);
    for ($d = $data['params']['disparity_min']; $d <= $data['params']['disparity_max']; $d++) $lines[] = 'histogram ' . $d . ' ' . ($counts[$d] ?? 0);
    return $lines;
}

function errorImage(array $image, array $truth): array
{
    $result = [];
    foreach ($image as $p => $actual) {
        $result[] = $truth[$p] === 0 ? 0 : ($actual === 0 ? 255 : 50 * (min(abs($actual - $truth[$p]), 3) + 1));
    }
    return $result;
}

function saveText(string $name, array $lines): void
{
    file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}

function main(): void
{
    $input = readPgm('input/left.pgm');
    $width = $input['width'];
    $height = $input['height'];
    $left = $input['pixels'];
    $right = readPgm('input/right.pgm')['pixels'];
    $truth = readPgm('input/ground_truth.pgm')['pixels'];
    $params = readParameters('input/params.txt');
    $data = compact('width', 'height', 'left', 'right', 'truth', 'params') + [
        'regions' => truthRegions($truth, $width, $height),
        'strengths' => texture($left, $width, $height, $params['texture_window']),
        'censusLeft' => census($left, $width, $height), 'censusRight' => census($right, $width, $height)];
    $choice = chooseWindows($data);
    $methods = $choice['methods'];
    $sgm = semiGlobal($data);
    $methods['sgm'] = $sgm['selected'];
    $methods['fusion'] = fuse($methods, $params['fusion_min_votes']);
    $methods['wta_final'] = postprocess($methods[$params['wta_cost']], $data);
    $methods['sgm_final'] = postprocess($methods['sgm'], $data);
    $objects = extractObjects($methods['sgm_final']['image'], $data);
    if (!is_dir('output')) mkdir('output', 0777, true);
    writePgm('output/disparity_wta.pgm', $width, $height, array_map(fn($d) => 8 * $d, $methods['wta_final']['image']));
    writePgm('output/disparity_sgm.pgm', $width, $height, array_map(fn($d) => 8 * $d, $methods['sgm_final']['image']));
    writePgm('output/occlusion.pgm', $width, $height, $methods['sgm']['reasons']);
    writePgm('output/error_sgm.pgm', $width, $height, errorImage($methods['sgm_final']['image'], $truth));
    saveText('depth.csv', sampleLines($methods, $sgm['summedCosts'], $data));
    saveText('evaluation.txt', evaluationLines($methods, $choice['sweeps'], $sgm['progress'], $data));
    saveText('objects.txt', objectLines($objects));
}

main();
