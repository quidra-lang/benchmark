<?php

function correlation(array $first, array $second): float
{
    $a = sequentialSum($first) / count($first);
    $b = sequentialSum($second) / count($second);
    $cross = $sx = $sy = 0.0;
    foreach ($first as $i => $value) {
        $cross += ($value - $a) * ($second[$i] - $b);
        $sx += ($value - $a) * ($value - $a);
        $sy += ($second[$i] - $b) * ($second[$i] - $b);
    }
    return $cross / sqrt($sx * $sy);
}

function contingencyTable(array $first, array $second, int $rows, int $columns): array
{
    $table = array_fill(0, $rows, array_fill(0, $columns, 0));
    foreach ($first as $i => $a) {
        ++$table[$a][$second[$i]];
    }
    return $table;
}

function pairCount(int $size): int
{
    return intdiv($size * ($size - 1), 2);
}

function adjustedRandIndex(array $table): array
{
    $count = $same = $rowPairs = $columnPairs = 0;
    $columns = array_fill(0, count($table[0]), 0);
    foreach ($table as $row) {
        $total = 0;
        foreach ($row as $b => $value) {
            $total += $value;
            $same += pairCount($value);
            $columns[$b] += $value;
        }
        $count += $total;
        $rowPairs += pairCount($total);
    }
    foreach ($columns as $value) {
        $columnPairs += pairCount($value);
    }
    $z = pairCount($count);
    $numerator = 2 * ($z * $same - $rowPairs * $columnPairs);
    $denominator = $z * ($rowPairs + $columnPairs) - 2 * $rowPairs * $columnPairs;
    if ($denominator === 0) {
        return [1, 1];
    }
    [$a, $b] = [abs($numerator), abs($denominator)];
    while ($b !== 0) {
        [$a, $b] = [$b, $a % $b];
    }
    if ($denominator < 0) {
        $a = -$a;
    }
    return [intdiv($numerator, $a), intdiv($denominator, $a)];
}

function silhouetteValues(array $partition, int $groups, array $delta): array
{
    $sizes = array_fill(0, $groups + 1, 0);
    foreach ($partition as $g) {
        ++$sizes[$g];
    }
    $values = [];
    foreach ($partition as $i => $own) {
        if ($sizes[$own] === 1) {
            $values[] = 0.0;
            continue;
        }
        $sums = array_fill(0, $groups + 1, 0.0);
        foreach ($partition as $j => $other) {
            if ($j !== $i) {
                $sums[$other] += $delta[$i][$j];
            }
        }
        $inner = $sums[$own] / ($sizes[$own] - 1);
        $outer = INF;
        for ($g = 1; $g <= $groups; ++$g) {
            if ($g !== $own) {
                $outer = min($outer, $sums[$g] / $sizes[$g]);
            }
        }
        $values[] = ($outer - $inner) / max($inner, $outer);
    }
    return $values;
}
