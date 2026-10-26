<?php

$limit = 200;
$prime = array_fill(0, $limit + 1, true);
$prime[0] = $prime[1] = false;
for ($p = 2; $p <= $limit; $p++) {
    if ($prime[$p]) {
        for ($multiple = 2 * $p; $multiple <= $limit; $multiple += $p) {
            $prime[$multiple] = false;
        }
    }
}
$primes = [];
for ($n = 2; $n <= $limit; $n++) {
    if ($prime[$n]) {
        $primes[] = $n;
    }
}
printf("count: %d\n", count($primes));
foreach (array_chunk($primes, 10) as $row) {
    echo implode(' ', $row), "\n";
}
