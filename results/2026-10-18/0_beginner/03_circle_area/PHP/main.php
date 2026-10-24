<?php
$pi = 3.141592653589793;
foreach ([3, 7, 12, 25, 41] as $radius) {
    $area = $pi * $radius * $radius;
    $circumference = 2 * $pi * $radius;
    printf("r=%d area=%.3F circumference=%.3F\n", $radius,
        $area, $circumference);
}
