<?php
declare(strict_types=1);

namespace CipherBenchmark;

function letter(string $char): bool
{
    $code = ord($char);
    return ($code >= 65 && $code <= 90) || ($code >= 97 && $code <= 122);
}

function value(string $char): int
{
    $code = ord($char);
    return $code >= 97 ? $code - 97 : $code - 65;
}

function upper(int $number): string
{
    return chr(65 + $number);
}

function letters(string $text): string
{
    return strtoupper((string) preg_replace('/[^A-Za-z]/', '', $text));
}

function grouped(string $text): array
{
    $lines = [];
    foreach (array_chunk(str_split($text, 5), 10) as $groups) {
        $lines[] = implode(' ', $groups);
    }
    return $lines;
}

function monogram(string $text, array $weights): int
{
    $sum = 0;
    for ($i = 0, $n = strlen($text); $i < $n; $i++) {
        $sum += $weights[ord($text[$i]) - 65];
    }
    return $sum;
}

function bigram(string $text, array $weights): int
{
    $sum = 0;
    for ($i = 1, $n = strlen($text); $i < $n; $i++) {
        $sum += $weights[ord($text[$i - 1]) - 65][ord($text[$i]) - 65];
    }
    return $sum;
}

function readWeights(string $path): array
{
    $lines = file($path, FILE_IGNORE_NEW_LINES);
    $mono = array_map('intval', explode(' ', $lines[1]));
    $bi = [];
    for ($i = 0; $i < 26; $i++) {
        $bi[] = array_map('intval', explode(' ', $lines[$i + 3]));
    }
    return [$mono, $bi];
}
