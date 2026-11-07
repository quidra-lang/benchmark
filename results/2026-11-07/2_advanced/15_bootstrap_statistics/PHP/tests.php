<?php

namespace Bootstrap;

function position_choices(int $total, int $size): \Generator
{
    $choice = range(0, $size - 1);
    while (true) {
        yield $choice;
        $index = $size - 1;
        while ($index >= 0 && $choice[$index] === $total - $size + $index) {
            $index--;
        }
        if ($index < 0) {
            return;
        }
        $choice[$index]++;
        for ($next = $index + 1; $next < $size; $next++) {
            $choice[$next] = $choice[$next - 1] + 1;
        }
    }
}

function reduced_fraction(int $a, int $b): array
{
    $x = abs($a);
    $y = $b;
    while ($y !== 0) {
        [$x, $y] = [$y, $x % $y];
    }
    return [intdiv($a, $x), intdiv($b, $x)];
}

function contrast(array $x, array $y): int
{
    return count($y) * array_sum($x) - count($x) * array_sum($y);
}

function value_counts(array $values): array
{
    $counts = [];
    foreach ($values as $value) {
        $counts[$value] = ($counts[$value] ?? 0) + 1;
    }
    ksort($counts, SORT_NUMERIC);
    return $counts;
}

function doubled_ranks(array $values): array
{
    $ranks = [];
    $smaller = 0;
    foreach (value_counts($values) as $value => $count) {
        $ranks[$value] = 2 * $smaller + $count + 1;
        $smaller += $count;
    }
    return array_map(fn($value) => $ranks[$value], $values);
}

function split_list(array $values, array $sizes): array
{
    $result = [];
    $offset = 0;
    foreach ($sizes as $size) {
        $result[] = array_slice($values, $offset, $size);
        $offset += $size;
    }
    return $result;
}

function anova(array $samples): array
{
    $count = array_sum(array_map('count', $samples));
    $grand = array_sum(array_map('array_sum', $samples)) / (100 * $count);
    $means = [];
    $between = 0.0;
    $within = 0.0;
    foreach ($samples as $sample) {
        $center = mean($sample);
        $means[] = $center;
        $difference = $center - $grand;
        $between += count($sample) * ($difference * $difference);
        $squares = 0.0;
        foreach ($sample as $value) {
            $e = $value / 100 - $center;
            $squares += $e * $e;
        }
        $within += $squares;
    }
    return ['count' => $count, 'means' => $means, 'ssb' => $between, 'ssw' => $within,
        'f' => $between / (count($samples) - 1) / ($within / ($count - count($samples)))];
}

function kruskal(array $rankGroups, float $correction): float
{
    $total = 0.0;
    $count = 0;
    foreach ($rankGroups as $ranks) {
        $rank = array_sum($ranks);
        $total += $rank * $rank / (4 * count($ranks));
        $count += count($ranks);
    }
    return (12 * $total / ($count * ($count + 1)) - 3 * ($count + 1)) / $correction;
}
