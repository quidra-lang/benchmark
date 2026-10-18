<?php
foreach ([-40, -15, -3, 0, 22, 37, 100] as $celsius) {
    $fahrenheit = $celsius * 9 / 5 + 32;
    printf("%d C = %.1F F\n", $celsius, round($fahrenheit, 1, PHP_ROUND_HALF_UP));
}
