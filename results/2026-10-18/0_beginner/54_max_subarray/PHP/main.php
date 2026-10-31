<?php

$arrays = [
    [3, -5, 8, -2, 6, -9, 4, 1, -7, 5, -3, 2],
    [-4, 7, -1, 3, -8, 10, -2, 5, -6, -2, 9, -12, 4, -1],
    [-6, -3, 5, -1, -4, 3, -9, 2, 3, -1, 4, -5, 1, 6, -2],
];
foreach ($arrays as $numbers) {
    $current = $best = $numbers[0];
    $start = $bestStart = $bestEnd = 0;
    for ($i = 1; $i < count($numbers); $i++) {
        if ($numbers[$i] > $current + $numbers[$i]) {
            $current = $numbers[$i];
            $start = $i;
        } else {
            $current += $numbers[$i];
        }
        if ($current > $best) {
            [$best, $bestStart, $bestEnd] = [$current, $start, $i];
        }
    }
    printf("max sum %d at [%d, %d]\n", $best, $bestStart, $bestEnd);
}
