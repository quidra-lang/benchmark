<?php
$deck = [];
foreach (str_split('SHDC') as $suit) {
    foreach (str_split('A23456789TJQK') as $rank) {
        $deck[] = $rank.$suit;
    }
}
$state = 2026;
for ($i = 51; $i >= 1; $i--) {
    $state = ($state*48271)%2147483647;
    $j = $state%($i+1);
    [$deck[$i],$deck[$j]] = [$deck[$j],$deck[$i]];
}
foreach (array_chunk($deck,13) as $row) echo implode(' ',$row), "\n";
