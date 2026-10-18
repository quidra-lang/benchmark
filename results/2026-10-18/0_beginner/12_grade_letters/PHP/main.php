<?php
$grades = ['A', 'B', 'C', 'D', 'F'];
$counts = array_fill(0, 5, 0);
foreach ([78, 90, 100, 59, 80, 85, 89, 70, 45, 93] as $score) {
    $index = $score >= 90 ? 0 : ($score >= 80 ? 1 : ($score >= 70 ? 2 : ($score >= 60 ? 3 : 4)));
    $counts[$index]++;
    printf("%d: %s\n", $score, $grades[$index]);
}
foreach ($grades as $index => $grade) printf("%s: %d\n", $grade, $counts[$index]);
