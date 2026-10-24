<?php
for ($n = 1; $n <= 30; $n++) {
    if ($n % 15 === 0) {
        echo "FizzBuzz\n";
    } elseif ($n % 3 === 0) {
        echo "Fizz\n";
    } elseif ($n % 5 === 0) {
        echo "Buzz\n";
    } else {
        printf("%d\n", $n);
    }
}
