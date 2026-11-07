<?php

$values = [17, -8, 42, 5, -23, 36, 5, 0, -11, 29];
$sum = array_sum($values);
printf("sum: %d\nmax: %d\nmin: %d\n", $sum, max($values), min($values));
