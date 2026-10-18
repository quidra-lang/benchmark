<?php
$values = [48, 73, 56, 91, 35, 62, 84];
$mean = array_sum($values) / count($values);
printf("%.2F\n", round($mean, 2, PHP_ROUND_HALF_UP));
