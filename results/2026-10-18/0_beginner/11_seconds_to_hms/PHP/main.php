<?php

foreach ([0, 59, 3725, 45296, 86400, 312047] as $seconds) {
    $hours = intdiv($seconds, 3600);
    $minutes = intdiv($seconds % 3600, 60);
    printf("%d seconds = %02d:%02d:%02d\n", $seconds, $hours, $minutes, $seconds % 60);
}
