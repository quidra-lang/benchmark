<?php
$matrix = [[125,340,78,912,456],[603,27,819,150,384],[0,765,231,498,62],[947,113,586,39,720]];
$columns = array_fill(0,5,0); $total = 0;
foreach ($matrix as $row) {
    $rowSum = 0;
    foreach ($row as $j => $value) {
        $rowSum += $value; $columns[$j] += $value;
        printf('%6d', $value);
    }
    $total += $rowSum;
    printf("%6d\n", $rowSum);
}
foreach ($columns as $value) printf('%6d', $value);
printf("%6d\n", $total);
