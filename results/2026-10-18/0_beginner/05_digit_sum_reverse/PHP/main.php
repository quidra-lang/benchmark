<?php
foreach ([7, 98000, 4096, 50301, 2718281, 123456789] as $original) {
    $digits = str_split((string) $original);
    printf("%d: digits=%d sum=%d reversed=%d\n", $original, count($digits), array_sum($digits), (int) strrev((string) $original));
}
