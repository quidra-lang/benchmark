<?php

function lowerBound(string $sequence, FMIndex $reverse): array
{
    $D = [];
    $z = 0;
    $lo = 0;
    $hi = strlen($reverse->text);
    for ($i = 0; $i < strlen($sequence); $i++) {
        [$lo, $hi] = $reverse->extend($lo, $hi, $sequence[$i]);
        if ($lo >= $hi) {
            $z++;
            $lo = 0;
            $hi = strlen($reverse->text);
        }
        $D[] = $z;
    }
    return $D;
}

function backtrack(string $sequence, int $maximum, FMIndex $forward, FMIndex $reverse): object
{
    $D = lowerBound($sequence, $reverse);
    $stack = [[strlen($sequence) - 1, $maximum, 0, strlen($forward->text)]];
    $leaves = [];
    $nodes = 0;
    $hits = 0;
    while ($stack) {
        [$i, $z, $lo, $hi] = array_pop($stack);
        $nodes++;
        if ($z < ($i < 0 ? 0 : $D[$i])) {
            continue;
        }
        if ($i === -1) {
            $leaves[] = (object) ['lo' => $lo, 'hi' => $hi, 'mismatches' => $maximum - $z];
            $hits += $hi - $lo;
            continue;
        }
        foreach (str_split('TGCA') as $base) {
            [$nextLo, $nextHi] = $forward->extend($lo, $hi, $base);
            if ($nextLo >= $nextHi) {
                continue;
            }
            if ($base === $sequence[$i]) {
                $stack[] = [$i - 1, $z, $nextLo, $nextHi];
            } elseif ($z >= 1) {
                $stack[] = [$i - 1, $z - 1, $nextLo, $nextHi];
            }
        }
    }
    return (object) ['nodes' => $nodes, 'leaves' => $leaves, 'hits' => $hits];
}
