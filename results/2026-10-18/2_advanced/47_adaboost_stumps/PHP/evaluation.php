<?php

function fixed($value, $digits = 4)
{
    if ($value === null) return '-';
    $result = sprintf('%.' . $digits . 'F', $value);
    return $result === ('-0.' . str_repeat('0', $digits)) ? substr($result, 1) : $result;
}

function ratio($numerator, $denominator)
{
    return $denominator > 0 ? fixed($numerator / $denominator) : '-';
}

function prediction($score)
{
    return $score > 0 ? 1 : -1;
}

function auc($rows, $scores)
{
    $positive = 0;
    $negative = 0;
    $wins = 0;
    $ties = 0;
    foreach ($rows as $row) {
        if ($row['label'] === 1) $positive++;
        else $negative++;
    }
    foreach ($rows as $a => $row) {
        if ($row['label'] !== 1) continue;
        foreach ($rows as $b => $other) {
            if ($other['label'] !== -1) continue;
            if ($scores[$a] > $scores[$b]) $wins++;
            elseif ($scores[$a] == $scores[$b]) $ties++;
        }
    }
    return ratio(2 * $wins + $ties, 2 * $positive * $negative);
}

function confusion($rows, $predictions, $classes)
{
    $matrix = array_fill(0, $classes, array_fill(0, $classes, 0));
    foreach ($rows as $i => $row) $matrix[$row['category'] - 1][$predictions[$i] - 1]++;
    return $matrix;
}

function count_at_most($values, $threshold)
{
    $count = 0;
    foreach ($values as $value) if ($value <= $threshold) $count++;
    return $count;
}

function write_lines($name, $lines)
{
    if (!is_dir('output')) mkdir('output', 0777, true);
    file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}
