<?php
$words = explode(' ', 'we planted beans and carrots in the garden behind our old house');
$longest = $shortest = $words[0]; $total = 0;
foreach ($words as $word) {
    $total += strlen($word);
    if (strlen($word) > strlen($longest)) $longest = $word;
    if (strlen($word) < strlen($shortest)) $shortest = $word;
}
$average = $total / count($words);
printf("words: %d\nlongest: %s\nshortest: %s\naverage length: %.2F\n", count($words), $longest, $shortest, round($average, 2, PHP_ROUND_HALF_UP));
