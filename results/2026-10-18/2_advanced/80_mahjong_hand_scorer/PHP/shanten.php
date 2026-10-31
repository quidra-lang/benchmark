<?php

namespace Shanten;

function patterns(array $counts, bool $suited): array
{
    static $cache = [];
    $key = implode(',', $counts) . ':' . (int) $suited;
    if (isset($cache[$key]))
        return $cache[$key];
    $first = null;
    foreach ($counts as $k => $n)
        if ($n) {
            $first = $k;
            break;
        }
    if ($first === null)
        return [[0, 0, 0]];
    $choices = [[[$first], 0, 0, 0]];
    if ($counts[$first] >= 3)
        $choices[] = [[$first, $first, $first], 1, 0, 0];
    if ($counts[$first] >= 2) {
        $choices[] = [[$first, $first], 0, 1, 0];
        $choices[] = [[$first, $first], 0, 0, 1];
    }
    if ($suited) {
        if ($first <= 6 && $counts[$first + 1] && $counts[$first + 2])
            $choices[] = [[$first, $first + 1, $first + 2], 1, 0, 0];
        foreach ([1, 2] as $d)
            if (($first + $d) < 9 && $counts[$first + $d])
                $choices[] = [[$first, $first + $d], 0, 1, 0];
    }
    $best = [];
    foreach ($choices as [$removed, $m, $t, $h]) {
        $remaining = $counts;
        foreach ($removed as $k)
            --$remaining[$k];
        foreach (patterns($remaining, $suited) as [$sets, $partial, $pair]) {
            $sets += $m;
            $pair += $h;
            if ($sets > 4 || $pair > 1)
                continue;
            $partial = min(4, $partial + $t);
            $state = $sets . ':' . $pair;
            if ($partial > ($best[$state][1] ?? -1))
                $best[$state] = [$sets, $partial, $pair];
        }
    }
    return $cache[$key] = array_values($best);
}

function standard(array $counts): int
{
    $states = [[0, 0, 0]];
    foreach ([[0, 9], [9, 9], [18, 9], [27, 7]] as [$start, $length]) {
        $local = patterns(array_slice($counts, $start, $length), $start < 27);
        $combined = [];
        foreach ($states as [$m, $t, $h])
            foreach ($local as [$lm, $lt, $lh]) {
                $sets = $m + $lm;
                $pair = $h + $lh;
                if ($sets > 4 || $pair > 1)
                    continue;
                $partial = min(4, $t + $lt);
                $key = $sets . ':' . $pair;
                if ($partial > ($combined[$key][1] ?? -1))
                    $combined[$key] = [$sets, $partial, $pair];
            }
        $states = array_values($combined);
    }
    return min(array_map(fn($s) => 8 - (2 * $s[0]) - min($s[1], 4 - $s[0]) - $s[2], $states));
}

function numbers(array $counts): array
{
    static $cache = [];
    $key = implode(',', $counts);
    if (isset($cache[$key]))
        return $cache[$key];
    $pairs = count(array_filter($counts, fn($n) => $n >= 2));
    $kinds = count(array_filter($counts));
    $seven = 6 - $pairs + max(0, 7 - $kinds);
    $orphans = 13;
    $pair = false;
    foreach (\Tiles\YAOCHUU as $k) {
        if ($counts[$k])
            --$orphans;
        if ($counts[$k] >= 2)
            $pair = true;
    }
    return $cache[$key] = [standard($counts), $seven, $orphans - (int) $pair];
}
