<?php

foreach ([[3, 8, 5], [6, 6, 6], [5, 8, 5], [13, 5, 12], [2, 9, 4], [7, 4, 7], [8, 6, 7], [4, 9, 6]] as $sides) {
    $ordered = $sides;
    sort($ordered, SORT_NUMERIC);
    [$a, $b, $c] = $ordered;
    if ($a + $b <= $c) {
        $result = 'not a triangle';
    } else {
        $side = $a === $c ? 'equilateral' : (($a === $b || $b === $c) ? 'isosceles' : 'scalene');
        $squareSum = $a * $a + $b * $b;
        $angle = $c * $c < $squareSum ? 'acute' : ($c * $c === $squareSum ? 'right' : 'obtuse');
        $result = $side . ' ' . $angle;
    }
    echo implode(' ', $sides), ': ', $result, "\n";
}
