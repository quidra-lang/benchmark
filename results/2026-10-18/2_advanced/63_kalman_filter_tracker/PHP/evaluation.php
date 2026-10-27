<?php

function distance($first, $second)
{
    $x = $first[0] - $second[0];
    $y = $first[1] - $second[1];
    return sqrt($x * $x + $y * $y);
}

function ospa($first, $second, $cutoff)
{
    if (count($first) === 0 && count($second) === 0) {
        return 0.0;
    }
    if (count($first) === 0 || count($second) === 0) {
        return $cutoff;
    }
    [$small, $large] = count($first) <= count($second) ? [$first, $second] : [$second, $first];
    $costs = [];
    foreach ($small as $point) {
        $row = [];
        foreach ($large as $other) {
            $d = min($cutoff, distance($point, $other));
            $row[] = $d * $d;
        }
        $costs[] = $row;
    }
    $total = 0.0;
    foreach (minimumMatching($costs) as [$i, $j]) {
        $total += $costs[$i][$j];
    }
    return sqrt(($total + $cutoff * $cutoff * (count($large) - count($small))) / count($large));
}

function continuity($labels)
{
    $covered = $groups = $swaps = 0;
    $delay = $previousLabel = null;
    $previousCovered = false;
    foreach ($labels as $i => $label) {
        if ($label === null) {
            $previousCovered = false;
            continue;
        }
        if ($delay === null) {
            $delay = $i;
        }
        $covered++;
        if (!$previousCovered) {
            $groups++;
        }
        if ($previousLabel !== null && $previousLabel !== $label) {
            $swaps++;
        }
        $previousLabel = $label;
        $previousCovered = true;
    }
    return ['covered' => $covered, 'breaks' => max(0, $groups - 1), 'swaps' => $swaps, 'delay' => $delay];
}

function fixed($value)
{
    $result = number_format(abs($value), 4, '.', '');
    return $value < 0 && $result !== '0.0000' ? '-' . $result : $result;
}
