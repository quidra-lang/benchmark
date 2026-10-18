<?php
$terms = [1, 1];
while (count($terms) < 30) {
    $n = count($terms);
    $terms[] = $terms[$n-2] + $terms[$n-1];
}
echo implode(" ", $terms), "\n";
printf("sum: %d\n", array_sum($terms));
