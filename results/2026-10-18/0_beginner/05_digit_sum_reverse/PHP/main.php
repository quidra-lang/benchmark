<?php
foreach ([7, 98000, 4096, 50301, 2718281, 123456789] as $original) {
    $remaining = $original;
    $count = $digitSum = $reversed = 0;
    while ($remaining > 0) {
        $digit = $remaining % 10;
        $count++;
        $digitSum += $digit;
        $reversed = $reversed * 10 + $digit;
        $remaining = intdiv($remaining, 10);
    }
    printf("%d: digits=%d sum=%d reversed=%d\n", $original, $count, $digitSum, $reversed);
}
