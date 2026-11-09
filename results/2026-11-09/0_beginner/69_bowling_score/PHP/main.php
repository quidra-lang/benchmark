<?php

$games = [
    [8, 1, 10, 7, 3, 9, 0, 10, 10, 2, 6, 6, 4, 0, 9, 10, 7, 2],
    [3, 4, 5, 2, 7, 1, 0, 6, 8, 1, 4, 4, 2, 3, 6, 2, 9, 0, 1, 5],
    [5, 5, 0, 10, 7, 3, 9, 1, 6, 4, 8, 2, 3, 7, 4, 6, 1, 9, 7, 3, 5],
    [10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10],
    [10, 9, 1, 10, 10, 7, 2, 0, 0, 10, 8, 1, 10, 6, 4, 10],
];
foreach ($games as $number => $rolls) {
    $position = $total = 0;
    $cumulative = [];
    for ($frame = 1; $frame <= 9; $frame++) {
        if ($rolls[$position] === 10) {
            $score = 10 + $rolls[$position + 1] + $rolls[$position + 2];
            $position++;
        } elseif ($rolls[$position] + $rolls[$position + 1] === 10) {
            $score = 10 + $rolls[$position + 2];
            $position += 2;
        } else {
            $score = $rolls[$position] + $rolls[$position + 1];
            $position += 2;
        }
        $total += $score;
        $cumulative[] = $total;
    }
    $cumulative[] = $total + array_sum(array_slice($rolls, $position));
    printf("game %d: %s\n", $number + 1, implode(' ', $cumulative));
}
