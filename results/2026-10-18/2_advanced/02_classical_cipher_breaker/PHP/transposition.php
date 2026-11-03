<?php
declare(strict_types=1);

namespace CipherBenchmark;

function railNumber(int $index, int $rails): int
{
    $cycle = 2 * $rails - 2;
    $position = $index % $cycle;
    return min($position, $cycle - $position);
}

function railFence(string $text, int $rails, bool $encrypt): string
{
    $order = range(0, strlen($text) - 1);
    usort($order, fn(int $a, int $b): int =>
        railNumber($a, $rails) <=> railNumber($b, $rails) ?: $a <=> $b);
    $result = array_fill(0, strlen($text), '');
    foreach ($order as $index => $position) {
        if ($encrypt) {
            $result[$index] = $text[$position];
        } else {
            $result[$position] = $text[$index];
        }
    }
    return implode('', $result);
}

function columnOrder(string $key): array
{
    $order = range(0, strlen($key) - 1);
    usort($order, fn(int $a, int $b): int => strcmp($key[$a], $key[$b]) ?: $a <=> $b);
    return $order;
}

function rankString(string $key): string
{
    $rank = array_fill(0, strlen($key), '');
    foreach (columnOrder($key) as $position => $column) {
        $rank[$column] = chr(49 + $position);
    }
    return implode('', $rank);
}

function columnar(string $text, string $key, bool $encrypt): string
{
    $result = array_fill(0, strlen($text), '');
    $pointer = 0;
    foreach (columnOrder($key) as $column) {
        for ($i = $column; $i < strlen($text); $i += strlen($key)) {
            if ($encrypt) {
                $result[$pointer++] = $text[$i];
            } else {
                $result[$i] = $text[$pointer++];
            }
        }
    }
    return implode('', $result);
}
