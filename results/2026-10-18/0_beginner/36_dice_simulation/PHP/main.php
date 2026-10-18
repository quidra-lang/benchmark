<?php
$state = 12345; $counts = array_fill(0,13,0);
for ($trial = 0; $trial < 1000; $trial++) {
    $state = ($state*48271)%2147483647; $first = $state%6+1;
    $state = ($state*48271)%2147483647; $second = $state%6+1;
    $counts[$first+$second]++;
}
$best = 2;
for ($total = 2; $total <= 12; $total++) {
    printf("%d: %d\n",$total,$counts[$total]);
    if ($counts[$total] > $counts[$best]) $best = $total;
}
printf("most frequent: %d\n",$best);
