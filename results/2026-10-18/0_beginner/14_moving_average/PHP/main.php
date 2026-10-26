<?php

$sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176];
for ($day = 3; $day <= count($sales); $day++) {
    $average = ($sales[$day - 3] + $sales[$day - 2] + $sales[$day - 1]) / 3;
    printf("day %d: %.2F\n", $day, $average);
}
