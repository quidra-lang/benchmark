<?php

$numbers = [72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71];
$average = array_sum($numbers) / count($numbers);
$squares = 0.0;
foreach ($numbers as $value) {
    $difference = $value - $average;
    $squares += $difference * $difference;
}
$deviation = sqrt($squares / count($numbers));
$ordered = $numbers;
sort($ordered, SORT_NUMERIC);
$frequencies = array_count_values($numbers);
ksort($frequencies, SORT_NUMERIC);
$mode = array_search(max($frequencies), $frequencies, true);
printf(
    "mean: %.3F\nmedian: %d\nmode: %d\nrange: %d\nstdev: %.3F\n",
    $average,
    $ordered[5],
    $mode,
    max($numbers) - min($numbers),
    $deviation,
);
