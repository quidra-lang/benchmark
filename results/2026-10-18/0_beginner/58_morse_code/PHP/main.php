<?php

$alphabet = str_split('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789');
$codes = explode(' ', '.- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. ----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----.');
$table = array_combine($alphabet, $codes);
$reverseTable = array_flip($table);
$message = 'MEET ME AT PIER 9 AT 1745';
$encoded = implode(' / ', array_map(
    fn($word) => implode(' ', array_map(fn($letter) => $table[$letter], str_split($word))),
    explode(' ', $message),
));
$decoded = implode(' ', array_map(
    fn($word) => implode('', array_map(fn($code) => $reverseTable[$code], explode(' ', $word))),
    explode(' / ', $encoded),
));
echo $encoded, "\n", $decoded, "\n";
