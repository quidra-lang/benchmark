<?php

function ledgerHash(string $text): string
{
    $bases = [1000003, 1500007, 2750159, 4194301];
    $initials = [11, 23, 37, 53];
    $result = '';
    foreach ($bases as $lane => $base) {
        $value = $initials[$lane];
        for ($i = 0; $i < strlen($text); $i++) {
            $value = ($value * $base + ord($text[$i])) % 2147483647;
        }
        foreach ([strlen($text), 0, 0] as $suffix) {
            $value = ($value * $base + $suffix) % 2147483647;
        }
        $result .= sprintf('%08x', $value);
    }
    return $result;
}

function merkleRoot(array $hashes): string
{
    while (count($hashes) > 1) {
        if (count($hashes) % 2 !== 0) {
            $hashes[] = $hashes[count($hashes) - 1];
        }
        $next = [];
        for ($i = 0; $i < count($hashes); $i += 2) {
            $next[] = ledgerHash($hashes[$i] . $hashes[$i + 1]);
        }
        $hashes = $next;
    }
    return $hashes[0];
}

function shortHash(string $value): string
{
    return substr($value, 0, 8);
}
