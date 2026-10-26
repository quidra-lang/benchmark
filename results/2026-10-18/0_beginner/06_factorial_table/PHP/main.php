<?php

$value = 1;
for ($n = 0; $n <= 12; $n++) {
    if ($n > 0) {
        $value *= $n;
    }
    printf("%d! = %d\n", $n, $value);
}
