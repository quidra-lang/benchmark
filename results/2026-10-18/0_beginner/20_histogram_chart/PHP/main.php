<?php
$days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
$amounts = [7,12,4,15,9,18,11];
foreach ($days as $i => $day) printf("%s | %s %d\n", $day, str_repeat('*', $amounts[$i]), $amounts[$i]);
