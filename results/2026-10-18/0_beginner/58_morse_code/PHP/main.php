<?php
$alphabet = str_split('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789');
$codes = explode(' ','.- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. ----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----.');
$table = array_combine($alphabet,$codes); $reverseTable = array_flip($table);
$message = 'MEET ME AT PIER 9 AT 1745'; $words = [];
foreach (explode(' ',$message) as $word) {
    $letters = []; foreach (str_split($word) as $letter) $letters[] = $table[$letter];
    $words[] = implode(' ',$letters);
}
$encoded = implode(' / ',$words); $decodedWords = [];
foreach (explode(' / ',$encoded) as $word) {
    $letters = []; foreach (explode(' ',$word) as $code) $letters[] = $reverseTable[$code];
    $decodedWords[] = implode('',$letters);
}
echo $encoded, "\n", implode(' ',$decodedWords), "\n";
