<?php

function encode(string $source): string
{
    return preg_replace_callback('/([A-Z])\1*/', fn($run) => strlen($run[0]) . $run[1], $source);
}

function decode(string $encoded): string
{
    return preg_replace_callback('/([0-9]+)([A-Z])/', fn($run) => str_repeat($run[2], (int) $run[1]), $encoded);
}

$sources = [
    'AAABBBCCCD', 'WWWWWWWWWWWWBWWWWWWWWWWWWBBB', 'ALGORITHM', 'MISSISSIPPI',
    'XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ',
];
foreach ($sources as $source) {
    $encoded = encode($source);
    printf("%s -> %s -> %s\n", $source, $encoded, decode($encoded));
}
