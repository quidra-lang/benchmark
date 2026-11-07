<?php

$text = 'The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.';
preg_match_all('/[a-z]+/', strtolower($text), $matches);
$frequencies = array_count_values($matches[0]);
$words = array_keys($frequencies);
usort($words, fn($a, $b) => ($frequencies[$b] <=> $frequencies[$a]) ?: strcmp($a, $b));
foreach (array_slice($words, 0, 5) as $word) {
    printf("%s: %d\n", $word, $frequencies[$word]);
}
printf("distinct words: %d\n", count($frequencies));
