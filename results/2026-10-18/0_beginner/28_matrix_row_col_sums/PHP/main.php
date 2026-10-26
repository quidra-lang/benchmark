<?php

$matrix = [[125, 340, 78, 912, 456], [603, 27, 819, 150, 384], [0, 765, 231, 498, 62], [947, 113, 586, 39, 720]];
$columns = array_map(fn($j) => array_sum(array_column($matrix, $j)), range(0, 4));
foreach ([...$matrix, $columns] as $row) {
    foreach ([...$row, array_sum($row)] as $value) {
        printf('%6d', $value);
    }
    echo "\n";
}
