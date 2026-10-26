<?php

foreach ([1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100] as $year) {
    $leap = $year % 400 === 0 || ($year % 4 === 0 && $year % 100 !== 0);
    printf("%04d: %s\n", $year, $leap ? "leap year" : "common year");
}
