<?php
$matrix = array_fill(0,5,array_fill(0,6,0));
$directions = [[0,1],[1,0],[0,-1],[-1,0]];
$row = $column = $direction = 0;
for ($value = 1; $value <= 30; $value++) {
    $matrix[$row][$column] = $value;
    if ($value === 30) break;
    [$dr,$dc] = $directions[$direction];
    $r = $row+$dr;
    $c = $column+$dc;
    if ($r < 0 || $r >= 5 || $c < 0 || $c >= 6 || $matrix[$r][$c] !== 0) {
        $direction = ($direction+1)%4;
        [$dr,$dc] = $directions[$direction];
    }
    $row += $dr;
    $column += $dc;
}
foreach ($matrix as $values) {
    foreach ($values as $value) printf('%3d',$value);
    echo "\n";
}
