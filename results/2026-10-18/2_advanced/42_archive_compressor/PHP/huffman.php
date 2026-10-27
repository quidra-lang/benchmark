<?php

function huffmanTreeLengths(array $frequencies): array
{
    $lengths = array_fill(0, count($frequencies), 0);
    $nodes = [];
    foreach ($frequencies as $symbol => $frequency) {
        if ($frequency > 0) {
            $nodes[] = ['weight' => $frequency, 'minimum' => $symbol, 'symbol' => $symbol];
        }
    }
    if (count($nodes) === 0) {
        return $lengths;
    }
    if (count($nodes) === 1) {
        $lengths[$nodes[0]['symbol']] = 1;
        return $lengths;
    }
    while (count($nodes) > 1) {
        usort($nodes, fn($a, $b) => ($a['weight'] <=> $b['weight']) ?: ($a['minimum'] <=> $b['minimum']));
        $first = array_shift($nodes);
        $second = array_shift($nodes);
        $nodes[] = ['weight' => $first['weight'] + $second['weight'],
            'minimum' => min($first['minimum'], $second['minimum']), 'first' => $first, 'second' => $second];
    }
    $stack = [[$nodes[0], 0]];
    while ($stack) {
        [$node, $depth] = array_pop($stack);
        if (isset($node['symbol'])) {
            $lengths[$node['symbol']] = $depth;
        } else {
            $stack[] = [$node['first'], $depth + 1];
            $stack[] = [$node['second'], $depth + 1];
        }
    }
    return $lengths;
}

function huffmanLimitedLengths(array $frequencies, int $limit): array
{
    $halvings = 0;
    while (true) {
        $lengths = huffmanTreeLengths($frequencies);
        if (max($lengths) <= $limit) {
            return ['lengths' => $lengths, 'halvings' => $halvings];
        }
        foreach ($frequencies as &$frequency) {
            $frequency = intdiv($frequency + 1, 2);
        }
        unset($frequency);
        $halvings++;
    }
}

function huffmanCanonical(array $lengths): array
{
    $symbols = [];
    foreach ($lengths as $symbol => $length) {
        if ($length > 0) {
            $symbols[] = $symbol;
        }
    }
    usort($symbols, fn($a, $b) => ($lengths[$a] <=> $lengths[$b]) ?: ($a <=> $b));
    $codes = array_fill(0, count($lengths), null);
    $value = 0;
    $previousLength = 0;
    foreach ($symbols as $index => $symbol) {
        $value = ($value + ($index > 0 ? 1 : 0)) << ($lengths[$symbol] - $previousLength);
        $codes[$symbol] = $value;
        $previousLength = $lengths[$symbol];
    }
    return $codes;
}
