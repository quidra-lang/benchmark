<?php

$board = array_fill(0, 11, array_fill(0, 11, false));
$row = $column = 5;
$direction = 0;
$directions = [[-1, 0], [0, 1], [1, 0], [0, -1]];
for ($step = 0; $step < 300; $step++) {
    $direction = ($direction + ($board[$row][$column] ? 3 : 1)) % 4;
    $board[$row][$column] = !$board[$row][$column];
    $row = ($row + $directions[$direction][0] + 11) % 11;
    $column = ($column + $directions[$direction][1] + 11) % 11;
}
$black = 0;
for ($r = 0; $r < 11; $r++) {
    for ($c = 0; $c < 11; $c++) {
        if ($board[$r][$c]) {
            $black++;
        }
        echo $r === $row && $c === $column ? 'A' : ($board[$r][$c] ? '#' : '.');
    }
    echo "\n";
}
printf("black: %d\n", $black);
