<?php
$words = explode(' ', 'we planted beans and carrots in the garden behind our old house');
$lengths = array_map('strlen', $words);
$longest = $words[array_search(max($lengths), $lengths, true)];
$shortest = $words[array_search(min($lengths), $lengths, true)];
$average = array_sum($lengths) / count($words);
printf("words: %d\nlongest: %s\nshortest: %s\naverage length: %.2F\n", count($words), $longest, $shortest, $average);
