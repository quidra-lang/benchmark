<?php
function caesar(string $message, int $shift): string {
    $shift = ($shift % 26 + 26) % 26;
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    $rotated = substr($alphabet, $shift) . substr($alphabet, 0, $shift);
    return strtr($message, $alphabet . strtolower($alphabet), $rotated . strtolower($rotated));
}
$ciphertext = caesar('Zoe, meet Max by the Old Bridge at six!', 3);
echo $ciphertext, "\n", caesar($ciphertext, -3), "\n";
