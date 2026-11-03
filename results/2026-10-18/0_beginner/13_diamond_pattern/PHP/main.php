<?php

$n = 5;
foreach (array_merge(range(1, $n), range($n - 1, 1)) as $i) {
    echo str_repeat(' ', $n - $i), str_repeat('*', 2 * $i - 1), "\n";
}
