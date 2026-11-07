<?php

$groups = [];
$words = [
    'listen', 'stone', 'night', 'silent', 'notes', 'apple', 'thing', 'enlist', 'earth', 'onset',
    'heart', 'tones',
];
foreach ($words as $word) {
    $letters = str_split($word);
    sort($letters, SORT_STRING);
    $signature = implode('', $letters);
    $groups[$signature][] = $word;
}
foreach ($groups as $group) {
    echo implode(' ', $group), "\n";
}
