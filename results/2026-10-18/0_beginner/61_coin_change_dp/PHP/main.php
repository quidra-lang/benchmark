<?php

$coins = [1, 5, 6, 9];
foreach ([8, 11, 15, 22, 33, 40] as $amount) {
    $minimums = array_fill(0, $amount + 1, $amount + 1);
    $minimums[0] = 0;
    for ($value = 1; $value <= $amount; $value++) {
        foreach ($coins as $coin) {
            if ($coin <= $value) {
                $minimums[$value] = min($minimums[$value], $minimums[$value - $coin] + 1);
            }
        }
    }
    $ways = array_fill(0, $amount + 1, 0);
    $ways[0] = 1;
    foreach ($coins as $coin) {
        for ($value = $coin; $value <= $amount; $value++) {
            $ways[$value] += $ways[$value - $coin];
        }
    }
    $remaining = $amount;
    $greedy = 0;
    foreach (array_reverse($coins) as $coin) {
        $greedy += intdiv($remaining, $coin);
        $remaining %= $coin;
    }
    printf("%d: min=%d greedy=%d ways=%d\n", $amount, $minimums[$amount], $greedy, $ways[$amount]);
}
