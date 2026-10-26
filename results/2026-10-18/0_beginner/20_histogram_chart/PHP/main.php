<?php

$counts = ['Mon' => 7, 'Tue' => 12, 'Wed' => 4, 'Thu' => 15, 'Fri' => 9, 'Sat' => 18, 'Sun' => 11];
foreach ($counts as $day => $count) {
    printf("%s | %s %d\n", $day, str_repeat('*', $count), $count);
}
