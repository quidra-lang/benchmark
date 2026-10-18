<?php
$initial = ['.#......','..#.....','###.....','........','........','........','.....###','........'];
$board = array_map(fn($row) => array_map(fn($c) => $c === '#',str_split($row)),$initial);
for ($generation = 0; $generation <= 4; $generation++) {
    printf("generation %d\n",$generation);
    foreach ($board as $row) echo implode('',array_map(fn($live) => $live ? '#' : '.',$row)), "\n";
    if ($generation === 4) break;
    $following = array_fill(0,8,array_fill(0,8,false));
    for ($row = 0; $row < 8; $row++) {
        for ($column = 0; $column < 8; $column++) {
            $neighbors = 0;
            for ($dr = -1; $dr <= 1; $dr++) {
                for ($dc = -1; $dc <= 1; $dc++) {
                    $r = $row+$dr;
                    $c = $column+$dc;
                    if (($dr !== 0 || $dc !== 0) && $r >= 0 && $r < 8 && $c >= 0 && $c < 8 && $board[$r][$c]) $neighbors++;
                }
            }
            $following[$row][$column] = $neighbors === 3 || ($board[$row][$column] && $neighbors === 2);
        }
    }
    $board = $following;
}
$alive = 0;
foreach ($board as $row) {
    foreach ($row as $live) {
        if ($live) $alive++;
    }
}
printf("alive: %d\n",$alive);
