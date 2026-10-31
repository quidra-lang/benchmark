<?php
declare(strict_types=1);

namespace CipherBenchmark;

function frequency(string $text): array
{
    $counts = array_fill(0, 26, 0);
    for ($i = 0, $n = strlen($text); $i < $n; $i++) {
        $counts[ord($text[$i]) - 65]++;
    }
    return $counts;
}

function ioc(string $text): int
{
    $n = strlen($text);
    if ($n < 2) {
        return 0;
    }
    $sum = 0;
    foreach (frequency($text) as $count) {
        $sum += $count * ($count - 1);
    }
    return intdiv(100000 * $sum, $n * ($n - 1));
}

function column(string $text, int $length, int $column): string
{
    $output = '';
    for ($i = $column; $i < strlen($text); $i += $length) {
        $output .= $text[$i];
    }
    return $output;
}

function columnIocs(string $text, int $length): array
{
    $indices = [];
    for ($i = 0; $i < $length; $i++) {
        $indices[] = ioc(column($text, $length, $i));
    }
    return $indices;
}

function averageIoc(string $text, int $length): int
{
    return intdiv(array_sum(columnIocs($text, $length)), $length);
}

function gcd(int $first, int $second): int
{
    while ($second !== 0) {
        [$first, $second] = [$second, $first % $second];
    }
    return $first;
}

function kasiski(string $text): array
{
    $locations = [];
    for ($i = 0; $i + 2 < strlen($text); $i++) {
        $trigram = substr($text, $i, 3);
        $locations[$trigram][] = $i + 1;
    }
    ksort($locations, SORT_STRING);
    $repeats = [];
    $allGaps = [];
    foreach ($locations as $trigram => $positions) {
        if (count($positions) < 2) {
            continue;
        }
        $gaps = [];
        for ($i = 1; $i < count($positions); $i++) {
            $gaps[] = $positions[$i] - $positions[$i - 1];
        }
        $allGaps = array_merge($allGaps, $gaps);
        $divisor = array_reduce($gaps, fn(int $carry, int $gap): int =>
            gcd($carry, $gap), 0);
        $repeats[] = [$trigram, $positions, $gaps, $divisor];
    }
    return ['repeats' => $repeats, 'gaps' => $allGaps];
}

function kasiskiCount(array $data, int $length): int
{
    return count(array_filter($data['gaps'], fn(int $gap): bool => $gap % $length === 0));
}

function periodTable(string $text, int $maxlen, array $data): array
{
    $lines = [];
    for ($length = 1; $length <= $maxlen; $length++) {
        $columns = columnIocs($text, $length);
        $average = intdiv(array_sum($columns), $length);
        $lines[] = "L=$length ioc=$average kasiski=" . kasiskiCount($data, $length)
            . " cols=" . implode(',', $columns);
    }
    return $lines;
}

function kasiskiTable(array $data): array
{
    $lines = ['kasiski repeats=' . count($data['repeats'])
        . ' spacings=' . count($data['gaps'])];
    foreach ($data['repeats'] as [$text, $positions, $gaps, $divisor]) {
        $lines[] = "$text at=" . implode(',', $positions)
            . ' gaps=' . implode(',', $gaps) . " gcd=$divisor";
    }
    return $lines;
}

function topPairs(string $text, bool $digraphs): string
{
    $counts = [];
    $step = $digraphs ? 2 : 1;
    for ($i = 0; $i + 1 < strlen($text); $i += $step) {
        $pair = substr($text, $i, 2);
        $counts[$pair] = ($counts[$pair] ?? 0) + 1;
    }
    $items = array_keys($counts);
    usort($items, fn(string $a, string $b): int =>
        $counts[$b] <=> $counts[$a] ?: strcmp($a, $b));
    return implode(' ', array_map(
        fn(string $pair): string => "$pair:" . $counts[$pair], array_slice($items, 0, 10)));
}

function percentage(int $count, int $total): string
{
    $tenths = intdiv(2000 * $count + $total, 2 * $total);
    return intdiv($tenths, 10) . '.' . ($tenths % 10);
}

function analyze(string $text, int $maxlen, array $mono, array $bi): array
{
    $data = kasiski($text);
    $counts = frequency($text);
    $doubles = 0;
    $pairDoubles = 0;
    for ($i = 0; $i + 1 < strlen($text); $i++) {
        if ($text[$i] === $text[$i + 1]) {
            $doubles++;
            if ($i % 2 === 0) {
                $pairDoubles++;
            }
        }
    }
    $lines = [
        'letters=' . strlen($text),
        'ioc=' . ioc($text) . ' mono=' . monogram($text, $mono)
            . ' bigram=' . bigram($text, $bi),
        "doubles=$doubles pair_doubles=$pairDoubles distinct="
            . count(array_filter($counts, fn(int $n): bool => $n !== 0)),
    ];
    for ($i = 0; $i < 26; $i++) {
        $lines[] = upper($i) . ' ' . $counts[$i] . ' ' . percentage($counts[$i], strlen($text));
    }
    $lines[] = 'bigrams ' . topPairs($text, false);
    return array_merge($lines, periodTable($text, $maxlen, $data), kasiskiTable($data));
}
