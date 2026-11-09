<?php

$sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176];
$windowSize = 3;
for ($day = $windowSize; $day <= count($sales); $day++) {
    $average = array_sum(array_slice($sales, $day - $windowSize, $windowSize)) / $windowSize;
    printf("day %d: %.2F\n", $day, $average);
}
