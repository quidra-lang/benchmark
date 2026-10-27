<?php

function fold(string $text): string
{
    return strtr(strtolower($text), ['[' => '{', ']' => '}', '\\' => '|', '^' => '~']);
}

function digits(string $text): bool
{
    if ($text === '') return false;
    for ($i = 0; $i < strlen($text); $i++) {
        $c = ord($text[$i]);
        if ($c < 48 || $c > 57) return false;
    }
    return true;
}

function validNickname(string $text): bool
{
    if ($text === '') return false;
    for ($i = 0; $i < strlen($text); $i++) {
        $c = ord($text[$i]);
        $letter = ($c >= 65 && $c <= 90) || ($c >= 97 && $c <= 122);
        $special = str_contains('[]\\`_^{|}', $text[$i]);
        if (!$letter && !$special && !($i > 0 && (($c >= 48 && $c <= 57) || $c === 45))) return false;
    }
    return true;
}

function validChannel(string $text, int $maximum): bool
{
    return strlen($text) >= 2 && strlen($text) <= $maximum && $text[0] === '#' && !str_contains($text, ':');
}

function parseMessage(string $raw): ?array
{
    $position = 0;
    $length = strlen($raw);
    if ($raw[0] === ':') {
        $position = strpos($raw, ' ');
        if ($position === false) return null;
    }
    while ($position < $length && $raw[$position] === ' ') $position++;
    $start = $position;
    while ($position < $length && $raw[$position] !== ' ') $position++;
    if ($position === $start) return null;
    $command = strtoupper(substr($raw, $start, $position - $start));
    $parameters = [];
    while ($position < $length) {
        while ($position < $length && $raw[$position] === ' ') $position++;
        if ($position === $length) break;
        if ($raw[$position] === ':') {
            $parameters[] = substr($raw, $position + 1);
            break;
        }
        if (count($parameters) === 14) {
            $parameters[] = substr($raw, $position);
            break;
        }
        $start = $position;
        while ($position < $length && $raw[$position] !== ' ') $position++;
        $parameters[] = substr($raw, $start, $position - $start);
    }
    return [$command, $parameters];
}
