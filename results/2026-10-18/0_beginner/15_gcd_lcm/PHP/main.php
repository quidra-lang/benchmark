<?php
function euclid(int $a, int $b): int {
    while ($b !== 0) [$a, $b] = [$b, $a % $b];
    return $a;
}
foreach ([[48, 180], [1071, 462], [7, 91], [13, 97], [36288, 98280]] as [$a, $b]) {
    $divisor = euclid($a, $b);
    $multiple = intdiv($a, $divisor) * $b;
    printf("gcd(%d, %d) = %d, lcm(%d, %d) = %d\n", $a, $b, $divisor, $a, $b, $multiple);
}
