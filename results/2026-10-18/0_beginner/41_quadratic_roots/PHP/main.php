<?php

foreach ([[1, -3, -10], [-2, 5, 4], [3, 1, -2], [4, -12, 9], [1, 2, 5], [-2, 3, -4]] as [$a, $b, $c]) {
    $discriminant = $b * $b - 4 * $a * $c;
    printf('%d %d %d: ', $a, $b, $c);
    if ($discriminant > 0) {
        $first = (-$b + sqrt($discriminant)) / (2 * $a);
        $second = (-$b - sqrt($discriminant)) / (2 * $a);
        printf("x1 = %.4F, x2 = %.4F\n", max($first, $second), min($first, $second));
    } elseif ($discriminant === 0) {
        printf("x = %.4F\n", -$b / (2 * $a));
    } else {
        $real = -$b / (2 * $a);
        $imaginary = sqrt(-$discriminant) / (2 * abs($a));
        printf("x = %.4F + %.4Fi, %.4F - %.4Fi\n", $real, $imaginary, $real, $imaginary);
    }
}
