<?php

const SYMBOLS = '$#ACGT';

function countingSort(array $positions, array $keys, int $classes): array
{
    $counts = array_fill(0, $classes, 0);
    $offsets = array_fill(0, $classes, 0);
    $result = array_fill(0, count($positions), 0);
    foreach ($positions as $position) {
        $counts[$keys[$position]]++;
    }
    for ($i = 1; $i < $classes; $i++) {
        $offsets[$i] = $offsets[$i - 1] + $counts[$i - 1];
    }
    foreach ($positions as $position) {
        $key = $keys[$position];
        $result[$offsets[$key]++] = $position;
    }
    return $result;
}

function buildSuffixArray(string $text): object
{
    $length = strlen($text);
    $positions = range(0, $length - 1);
    $keys = [];
    for ($i = 0; $i < $length; $i++) {
        $keys[] = strpos(SYMBOLS, $text[$i]);
    }
    $order = countingSort($positions, $keys, 6);
    $rank = array_fill(0, $length, 0);
    $classes = 0;
    foreach ($order as $i => $position) {
        if ($i === 0 || $keys[$position] !== $keys[$order[$i - 1]]) {
            $classes++;
        }
        $rank[$position] = $classes - 1;
    }
    $rounds = [$classes];
    $prefix = 1;
    while ($classes < $length) {
        $second = [];
        for ($i = 0; $i < $length; $i++) {
            $second[] = $i + $prefix < $length ? $rank[$i + $prefix] + 1 : 0;
        }
        $order = countingSort(countingSort($positions, $second, $classes + 1), $rank, $classes);
        $next = array_fill(0, $length, 0);
        $count = 0;
        foreach ($order as $i => $position) {
            if ($i === 0 || $rank[$position] !== $rank[$order[$i - 1]] || $second[$position] !== $second[$order[$i - 1]]) {
                $count++;
            }
            $next[$position] = $count - 1;
        }
        $rank = $next;
        $classes = $count;
        $rounds[] = $classes;
        $prefix *= 2;
    }
    return (object) ['sa' => $order, 'rounds' => $rounds];
}

function checkSuffixArray(string $text, array $sa): object
{
    $n = strlen($text);
    $lcp = [0];
    $ordered = 0;
    $sum = 0;
    $maximum = -1;
    $bestRow = 1;
    for ($i = 1; $i < $n; $i++) {
        $first = $sa[$i - 1];
        $second = $sa[$i];
        $limit = min($n - $first, $n - $second);
        $length = 0;
        while ($length + 256 <= $limit
            && substr_compare($text, substr($text, $first + $length, 256), $second + $length, 256) === 0) {
            $length += 256;
        }
        while ($length < $limit && $text[$first + $length] === $text[$second + $length]) {
            $length++;
        }
        $lcp[] = $length;
        if (strpos(SYMBOLS, $text[$first + $length]) < strpos(SYMBOLS, $text[$second + $length])) {
            $ordered++;
        }
        $sum += $length;
        if ($length > $maximum) {
            $maximum = $length;
            $bestRow = $i;
        }
    }
    return (object) ['ordered' => $ordered, 'lcp' => $lcp, 'lcpSum' => $sum, 'maximum' => $maximum, 'row' => $bestRow];
}

function directSuffixArray(string $text): array
{
    $order = range(0, strlen($text) - 1);
    usort($order, fn($a, $b) => strcmp(substr($text, $a), substr($text, $b)));
    return $order;
}
