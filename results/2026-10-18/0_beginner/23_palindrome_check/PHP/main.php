<?php

$phrases = [
    'Never odd or even', 'Race a car', 'Was it a car or a cat I saw?', 'Hello, World!',
    'Step on no pets.', 'No lemon, no melon',
];
foreach ($phrases as $phrase) {
    $clean = strtolower(preg_replace('/[^A-Za-z]/', '', $phrase));
    printf("%s -> %s\n", $phrase, $clean === strrev($clean) ? 'yes' : 'no');
}
