<?php
$numbers = [27,64,13,88,41,5,72,36]; $total = 0;
for ($pass = 1; $pass <= 7; $pass++) {
    $changed = false;
    for ($j = 0; $j <= 7-$pass; $j++) {
        if ($numbers[$j] > $numbers[$j+1]) {
            [$numbers[$j],$numbers[$j+1]] = [$numbers[$j+1],$numbers[$j]];
            $total++; $changed = true;
        }
    }
    printf("pass %d: %s\n",$pass,implode(' ',$numbers));
    if (!$changed) break;
}
printf("swaps: %d\n",$total);
