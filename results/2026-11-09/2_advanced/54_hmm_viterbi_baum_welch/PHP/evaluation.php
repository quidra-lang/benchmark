<?php

function fraction($numerator, $denominator)
{
    if ($denominator === 0) return '-';
    $a = abs($numerator);
    $b = $denominator;
    while ($b !== 0) {
        $next = $a % $b;
        $a = $b;
        $b = $next;
    }
    return intdiv($numerator, $a) . '/' . intdiv($denominator, $a);
}

function confusion($size)
{
    return array_fill(0, $size, array_fill(0, $size, 0));
}

function accumulate(&$matrix, $truth, $prediction)
{
    $correct = 0;
    foreach ($truth as $t => $state) {
        $matrix[$state][$prediction[$t]]++;
        if ($state === $prediction[$t]) $correct++;
    }
    return $correct;
}

function confusion_lines($matrix, $states)
{
    $width = 1;
    foreach ($matrix as $row) foreach ($row as $value) $width = max($width, strlen((string) $value));
    $header = ' ';
    foreach ($states as $state) $header .= ' ' . str_pad($state, $width, ' ', STR_PAD_LEFT);
    $lines = [$header];
    foreach ($states as $i => $state) {
        $line = $state;
        foreach ($matrix[$i] as $value) $line .= ' ' . str_pad((string) $value, $width, ' ', STR_PAD_LEFT);
        $lines[] = $line;
    }
    return $lines;
}

function metric_lines($matrix, $states)
{
    $size = count($states);
    $rows = array_fill(0, $size, 0);
    $columns = array_fill(0, $size, 0);
    $total = 0;
    $correct = 0;
    for ($i = 0; $i < $size; $i++) {
        $correct += $matrix[$i][$i];
        for ($j = 0; $j < $size; $j++) {
            $rows[$i] += $matrix[$i][$j];
            $columns[$j] += $matrix[$i][$j];
            $total += $matrix[$i][$j];
        }
    }
    $chance = 0;
    for ($i = 0; $i < $size; $i++) $chance += $rows[$i] * $columns[$i];
    $lines = ['ACCURACY ' . fraction($correct, $total), 'KAPPA ' . fraction($total * $correct - $chance, $total * $total - $chance)];
    for ($i = 0; $i < $size; $i++) $lines[] = 'STATE ' . $states[$i] . ' precision ' . fraction($matrix[$i][$i], $columns[$i])
        . ' recall ' . fraction($matrix[$i][$i], $rows[$i]) . ' f1 ' . fraction(2 * $matrix[$i][$i], $columns[$i] + $rows[$i]);
    return $lines;
}

function runs($path)
{
    $result = [];
    $start = 0;
    for ($end = 1; $end <= count($path); $end++) {
        if ($end === count($path) || $path[$end] !== $path[$start]) {
            $result[] = ['state' => $path[$start], 'start' => $start, 'end' => $end - 1];
            $start = $end;
        }
    }
    return $result;
}

function overlaps($left, $right)
{
    return $left['start'] <= $right['end'] && $right['start'] <= $left['end'];
}

function boundaries($path)
{
    $result = [];
    for ($t = 1; $t < count($path); $t++) if ($path[$t - 1] !== $path[$t]) $result[] = $t + 1;
    return $result;
}

function matched_boundaries($source, $target, $tolerance)
{
    $count = 0;
    foreach ($source as $position) foreach ($target as $other) if (abs($position - $other) <= $tolerance) { $count++; break; }
    return $count;
}
