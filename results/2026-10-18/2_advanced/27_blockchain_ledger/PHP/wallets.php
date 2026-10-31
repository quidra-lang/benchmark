<?php

require_once __DIR__ . '/hashing.php';

function readWallets(): array
{
    $wallets = [];
    foreach (file('input/wallets.txt', FILE_IGNORE_NEW_LINES) as $line) {
        [$name, $secret] = explode(' ', $line);
        $wallets[] = ['name' => $name, 'secret' => $secret, 'address' => substr(ledgerHash('addr:' . $secret), 0, 16)];
    }
    return $wallets;
}

function signature(string $secret, int $index, string $body): string
{
    return substr(ledgerHash($secret . ':' . $index . ':' . $body), 0, 16);
}
