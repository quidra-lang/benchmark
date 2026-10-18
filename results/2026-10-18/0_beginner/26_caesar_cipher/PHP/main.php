<?php
function caesar(string $message, int $shift): string {
    $result = '';
    foreach (str_split($message) as $letter) {
        $code = ord($letter);
        if ($code >= 65 && $code <= 90) $letter = chr(65 + ($code-65+$shift+26) % 26);
        elseif ($code >= 97 && $code <= 122) $letter = chr(97 + ($code-97+$shift+26) % 26);
        $result .= $letter;
    }
    return $result;
}
$ciphertext = caesar('Zoe, meet Max by the Old Bridge at six!', 3);
echo $ciphertext, "\n", caesar($ciphertext, -3), "\n";
