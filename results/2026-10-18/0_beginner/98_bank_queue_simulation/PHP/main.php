<?php

$state = 42;
$arrival = $totalWait = $maxWait = 0;
$freeTimes = [0, 0];
for ($customer = 1; $customer <= 20; $customer++) {
    $state = ($state * 48271) % 2147483647;
    $arrival += $state % 5 + 1;
    $state = ($state * 48271) % 2147483647;
    $service = $state % 7 + 2;
    $teller = $freeTimes[0] <= $freeTimes[1] ? 0 : 1;
    $start = max($arrival, $freeTimes[$teller]);
    $departure = $start + $service;
    $wait = $start - $arrival;
    $freeTimes[$teller] = $departure;
    $totalWait += $wait;
    $maxWait = max($maxWait, $wait);
    printf(
        "customer %d: arrive=%d start=%d end=%d teller=%d wait=%d\n",
        $customer,
        $arrival,
        $start,
        $departure,
        $teller + 1,
        $wait,
    );
}
printf("average wait: %.2F\nmax wait: %d\nlast departure: %d\n", $totalWait / 20, $maxWait, max($freeTimes));
