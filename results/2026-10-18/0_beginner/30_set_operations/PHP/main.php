<?php

$a = array_unique([12, 5, 8, 21, 5, 17, 3, 12, 9]);
$b = array_unique([8, 14, 21, 6, 14, 3, 25, 6]);
$results = [
    array_unique(array_merge($a, $b)),
    array_intersect($a, $b),
    array_diff($a, $b),
    array_merge(array_diff($a, $b), array_diff($b, $a)),
];
$labels = ['union', 'intersection', 'difference', 'symmetric difference'];
foreach ($results as $i => $result) {
    sort($result, SORT_NUMERIC);
    echo $labels[$i], ': ', implode(' ', $result), "\n";
}
