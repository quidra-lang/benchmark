<?php
$numbers = [52,17,38,9,61,38,24,45]; $total = 0;
for ($i = 1; $i <= 7; $i++) {
    $value = $numbers[$i]; $j = $i-1; $shifts = 0;
    while ($j >= 0 && $numbers[$j] > $value) { $numbers[$j+1] = $numbers[$j]; $shifts++; $j--; }
    $numbers[$j+1] = $value; $total += $shifts;
    printf("i=%d shifts=%d: %s\n",$i,$shifts,implode(' ',$numbers));
}
printf("total shifts: %d\n",$total);
