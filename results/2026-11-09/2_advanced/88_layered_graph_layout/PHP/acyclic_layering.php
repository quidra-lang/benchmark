<?php

function neighbors(int $count, array $edges): array
{
    $upper = $lower = array_fill(0, $count, []);
    foreach ($edges as [$a, $b]) {
        $lower[$a][] = $b;
        $upper[$b][] = $a;
    }
    return [$upper, $lower];
}

function lexCompare(array $a, array $b): int
{
    for ($i = 0; $i < min(count($a), count($b)); ++$i)
        if ($a[$i] !== $b[$i])
            return $a[$i] <=> $b[$i];
    return count($a) <=> count($b);
}

function acyclicOrder(int $count, array $edges): array
{
    [$upper, $lower] = neighbors($count, $edges);
    $remaining = array_fill(0, $count, true);
    $head = $tail = [];
    while ($remaining) {
        $in = $out = [];
        $sink = $source = null;
        $best = null;
        foreach ($remaining as $v => $unused) {
            $in[$v] = count(array_intersect_key(array_fill_keys($upper[$v], true), $remaining));
            $out[$v] = count(array_intersect_key(array_fill_keys($lower[$v], true), $remaining));
            if ($out[$v] === 0 && $sink === null)
                $sink = $v;
            if ($in[$v] === 0 && $source === null)
                $source = $v;
            if ($best === null || ($out[$v] - $in[$v]) > ($out[$best] - $in[$best]))
                $best = $v;
        }
        if ($sink !== null) {
            $chosen = $sink;
            array_unshift($tail, $chosen);
        } else {
            $chosen = $source ?? $best;
            $head[] = $chosen;
        }
        unset($remaining[$chosen]);
    }
    return [...$head, ...$tail];
}

function assignHeights(int $count, array $edges, array $settings): array
{
    [$upper, $lower] = neighbors($count, $edges);
    $heights = array_fill(0, $count, null);
    $labels = null;
    if ($settings['layering'] === 'coffman') {
        $labels = array_fill(0, $count, null);
        for ($label = 1; $label <= $count; ++$label) {
            $chosen = $best = null;
            for ($v = 0; $v < $count; ++$v)
                if ($labels[$v] === null && array_all($upper[$v], fn($u) => $labels[$u] !== null)) {
                    $sequence = array_map(fn($u) => $labels[$u], $upper[$v]);
                    rsort($sequence, SORT_NUMERIC);
                    if ($chosen === null || lexCompare($sequence, $best) < 0) {
                        $chosen = $v;
                        $best = $sequence;
                    }
                }
            $labels[$chosen] = $label;
        }
        $current = $occupied = 0;
        for ($i = 0; $i < $count; ++$i) {
            $chosen = null;
            for ($v = 0; $v < $count; ++$v)
                if (
                    $heights[$v] === null
                    && array_all($lower[$v], fn($w) => $heights[$w] !== null)
                    && ($chosen === null || $labels[$v] > $labels[$chosen])
                )
                    $chosen = $v;
            if (
                $occupied === $settings['width']
                || array_any($lower[$chosen], fn($w) => $heights[$w] === $current)
            ) {
                ++$current;
                $occupied = 0;
            }
            $heights[$chosen] = $current;
            ++$occupied;
        }
    } else
        for ($i = 0; $i < $count; ++$i)
            for ($v = 0; $v < $count; ++$v)
                if ($heights[$v] === null && array_all($lower[$v], fn($w) => $heights[$w] !== null)) {
                    $values = array_map(fn($w) => $heights[$w] + 1, $lower[$v]);
                    $heights[$v] = $values ? max($values) : 0;
                    break;
                }
    $before = 0;
    foreach ($edges as [$a, $b])
        $before += $heights[$a] - $heights[$b] - 1;
    $rounds = 0;
    $record = [];
    $promote = function (int $v) use (&$promote, &$heights, $upper, $lower): int {
        $difference = 0;
        foreach ($upper[$v] as $u)
            if ($heights[$u] === ($heights[$v] + 1))
                $difference += $promote($u);
        ++$heights[$v];
        return $difference + count($lower[$v]) - count($upper[$v]);
    };
    if ($settings['promotion'] === 'on')
        do {
            ++$rounds;
            $accepted = 0;
            for ($v = 0; $v < $count; ++$v)
                if ($upper[$v]) {
                    $saved = $heights;
                    $difference = $promote($v);
                    if ($difference < 0) {
                        ++$accepted;
                        $record[] = [$rounds, $v, $difference];
                    } else
                        $heights = $saved;
                }
        } while ($accepted);
    return [$heights, $labels, $before, $rounds, $record];
}
