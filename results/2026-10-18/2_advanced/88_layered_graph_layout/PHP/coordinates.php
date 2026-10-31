<?php

const VARIANTS = ['ul', 'ur', 'dl', 'dr'];

function floorDiv(int $a, int $b): int
{
    $q = intdiv($a, $b);
    return $a < 0 && ($a % $b) !== 0 ? $q - 1 : $q;
}

function markConflicts(array $orders, array $upper, int $nodeCount, array $position): array
{
    $marked = [];
    for ($i = 0; $i < (count($orders) - 1); ++$i) {
        $a = $orders[$i];
        $b = $orders[$i + 1];
        $k0 = $start = 0;
        foreach ($b as $last => $v) {
            $inner = $v >= $nodeCount && $upper[$v][0] >= $nodeCount;
            if (!$inner && $last !== (count($b) - 1))
                continue;
            $k1 = $inner ? $position[$upper[$v][0]] : count($a) - 1;
            for ($j = $start; $j <= $last; ++$j)
                foreach ($upper[$b[$j]] as $u)
                    if ($position[$u] < $k0 || $position[$u] > $k1)
                        $marked[$u . ':' . $b[$j]] = true;
            $start = $last + 1;
            $k0 = $k1;
        }
    }
    return $marked;
}

function alignment(
    string $variant,
    array $orders,
    array $upper,
    array $lower,
    array $marked,
    int $count,
): array {
    $scan = array_map(fn($layer) => $variant[1] === 'l' ? $layer : array_reverse($layer), $orders);
    $rank = positions($scan);
    $root = $align = range(0, $count - 1);
    $layers = array_keys($orders);
    if ($variant[0] === 'd')
        $layers = array_reverse($layers);
    $reference = $variant[0] === 'u' ? $upper : $lower;
    foreach (array_slice($layers, 1) as $layer) {
        $rho = -1;
        foreach ($scan[$layer] as $v) {
            $neighbors = $reference[$v];
            usort($neighbors, fn($a, $b) => $rank[$a] <=> $rank[$b]);
            $n = count($neighbors);
            if (!$n)
                continue;
            foreach ([intdiv($n - 1, 2), intdiv($n, 2)] as $m) {
                $u = $neighbors[$m];
                $key = $variant[0] === 'u' ? $u . ':' . $v : $v . ':' . $u;
                if ($align[$v] === $v && !isset($marked[$key]) && $rho < $rank[$u]) {
                    $align[$u] = $v;
                    $root[$v] = $root[$u];
                    $align[$v] = $root[$v];
                    $rho = $rank[$u];
                }
            }
        }
    }
    return [$root, $scan];
}

function compactBlocks(
    array $root,
    array $scan,
    string $variant,
    array $left,
    array $right,
    int $nodeCount,
    array $settings,
): array {
    $blocks = array_values(array_unique($root));
    sort($blocks, SORT_NUMERIC);
    $out = $in = array_fill_keys($blocks, []);
    foreach ($scan as $layer)
        for ($i = 0; $i < (count($layer) - 1); ++$i) {
            $first = $layer[$i];
            $second = $layer[$i + 1];
            [$a, $b] = $variant[1] === 'l' ? [$first, $second] : [$second, $first];
            $gap = $a < $nodeCount && $b < $nodeCount ? $settings['node_sep'] : $settings['dummy_sep'];
            $distance = $right[$a] + $left[$b] + 1 + $gap;
            $origin = $root[$first];
            $target = $root[$second];
            $distance = max($distance, $out[$origin][$target] ?? $distance);
            $out[$origin][$target] = $in[$target][$origin] = $distance;
        }
    $pending = [];
    $ready = [];
    foreach ($blocks as $block) {
        $pending[$block] = count($in[$block]);
        if (!$pending[$block])
            $ready[] = $block;
    }
    $ordered = $y1 = $y2 = [];
    while ($ready) {
        $block = array_pop($ready);
        $ordered[] = $block;
        $best = 0;
        foreach ($in[$block] as $a => $delta)
            $best = max($best, $y1[$a] + $delta);
        $y1[$block] = $best;
        foreach ($out[$block] as $b => $delta)
            if (--$pending[$b] === 0)
                $ready[] = $b;
    }
    foreach (array_reverse($ordered) as $block) {
        $coordinate = $y1[$block];
        if ($out[$block]) {
            $values = [];
            foreach ($out[$block] as $b => $delta)
                $values[] = $y2[$b] - $delta;
            $coordinate = max($coordinate, min($values));
        }
        $y2[$block] = $coordinate;
    }
    $sign = $variant[1] === 'l' ? 1 : -1;
    return [array_map(fn($b) => $sign * $y2[$b], $root), count($blocks)];
}

function assignCoordinates(
    array $orders,
    array $upper,
    array $lower,
    array $widths,
    int $nodeCount,
    array $settings,
): object {
    $count = count($widths);
    $left = $right = [];
    foreach ($widths as $w) {
        $l = in_array($settings['direction'], ['TB', 'BT'], true) ? intdiv($w - 1, 2) : 0;
        $left[] = $l;
        $right[] = in_array($settings['direction'], ['TB', 'BT'], true) ? $w - 1 - $l : 0;
    }
    $conflicts = markConflicts($orders, $upper, $nodeCount, positions($orders));
    $layouts = $blocks = $bounds = $spans = [];
    $smallest = null;
    foreach (VARIANTS as $variant) {
        [$root, $scan] = alignment($variant, $orders, $upper, $lower, $conflicts, $count);
        [$layout, $blockCount] = compactBlocks($root, $scan, $variant, $left, $right, $nodeCount, $settings);
        $lo = PHP_INT_MAX;
        $hi = PHP_INT_MIN;
        foreach ($layout as $v => $x) {
            $lo = min($lo, $x - $left[$v]);
            $hi = max($hi, $x + $right[$v]);
        }
        $layouts[$variant] = $layout;
        $blocks[$variant] = $blockCount;
        $bounds[$variant] = [$lo, $hi];
        $spans[$variant] = $hi - $lo + 1;
        if ($smallest === null || $spans[$variant] < $spans[$smallest])
            $smallest = $variant;
    }
    $aligned = [];
    foreach (VARIANTS as $variant) {
        $side = $variant[1] === 'l' ? 0 : 1;
        $shift = $bounds[$smallest][$side] - $bounds[$variant][$side];
        $aligned[$variant] = array_map(fn($x) => $x + $shift, $layouts[$variant]);
    }
    $x = [];
    for ($v = 0; $v < $count; ++$v) {
        $values = [];
        foreach (VARIANTS as $variant)
            $values[] = $aligned[$variant][$v];
        sort($values, SORT_NUMERIC);
        $x[] = floorDiv($values[1] + $values[2], 2);
    }
    $lo = PHP_INT_MAX;
    foreach ($x as $v => $value)
        $lo = min($lo, $value - $left[$v]);
    $x = array_map(fn($value) => $value - $lo, $x);
    return (object) [
        'x' => $x,
        'left' => $left,
        'right' => $right,
        'aligned' => $aligned,
        'blocks' => $blocks,
        'widths' => $spans,
        'smallest' => $smallest,
        'conflicts' => $conflicts,
    ];
}
