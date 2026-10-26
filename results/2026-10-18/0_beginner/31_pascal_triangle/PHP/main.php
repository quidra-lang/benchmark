<?php

$row = [1];
for ($n = 0; $n <= 11; $n++) {
    echo implode(' ', $row), "\n";
    $next = array_fill(0, count($row) + 1, 1);
    for ($k = 1; $k < count($row); $k++) {
        $next[$k] = $row[$k - 1] + $row[$k];
    }
    $row = $next;
}
