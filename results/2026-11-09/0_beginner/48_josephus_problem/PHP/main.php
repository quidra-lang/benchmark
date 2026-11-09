<?php

foreach ([[7, 3], [10, 2], [41, 3]] as [$n, $k]) {
    $people = range(1, $n);
    $removed = [];
    $index = 0;
    while (count($people) > 0) {
        $index = ($index + $k - 1) % count($people);
        $removed[] = array_splice($people, $index, 1)[0];
    }
    printf("n=%d k=%d: %s\nsurvivor: %d\n", $n, $k, implode(' ', $removed), $removed[count($removed) - 1]);
}
