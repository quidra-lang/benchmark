<?php

function maskMatches(string $mask, string $text): bool
{
    $pattern = fold($mask);
    $value = fold($text);
    $i = $j = 0;
    $star = -1;
    $retry = 0;
    while ($j < strlen($value)) {
        if ($i < strlen($pattern) && $pattern[$i] !== '*' && ($pattern[$i] === '?' || $pattern[$i] === $value[$j])) {
            $i++;
            $j++;
        } elseif ($i < strlen($pattern) && $pattern[$i] === '*') {
            $star = $i++;
            $retry = $j;
        } elseif ($star >= 0) {
            $i = $star + 1;
            $j = ++$retry;
        } else return false;
    }
    while ($i < strlen($pattern) && $pattern[$i] === '*') $i++;
    return $i === strlen($pattern);
}

function normalizeMask(string $text): string
{
    $bang = str_contains($text, '!');
    $at = str_contains($text, '@');
    if ($bang && $at) return $text;
    if ($at) return '*!' . $text;
    if ($bang) return $text . '@*';
    return str_contains($text, '.') ? '*!*@' . $text : $text . '!*@*';
}
