<?php
$numbers = [12,5,12,8,3,5,20,8,8,15,3,7,20,12,9];
$remaining = array_values(array_unique($numbers));
echo implode(' ', $remaining), "\n";
printf("removed: %d\n", count($numbers)-count($remaining));
