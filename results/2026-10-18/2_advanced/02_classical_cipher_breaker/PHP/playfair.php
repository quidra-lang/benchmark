<?php
declare(strict_types=1);

namespace CipherBenchmark;

function square(string $key): string
{
    $result = '';
    $visited = [];
    $text = str_replace('J', 'I', strtoupper($key)) . 'ABCDEFGHIKLMNOPQRSTUVWXYZ';
    foreach (str_split($text) as $char) {
        if (!isset($visited[$char])) {
            $visited[$char] = true;
            $result .= $char;
        }
    }
    return $result;
}

function validPlayfair(string $text): bool
{
    $normalized = str_replace('J', 'I', $text);
    $length = strlen($normalized);
    if ($length % 2 !== 0) {
        return false;
    }
    for ($i = 0; $i < $length; $i += 2) {
        if ($normalized[$i] === $normalized[$i + 1]) {
            return false;
        }
    }
    return true;
}

function preparePlayfair(string $text): string
{
    $normalized = str_replace('J', 'I', $text);
    $result = '';
    for ($i = 0, $length = strlen($normalized); $i < $length;) {
        $first = $normalized[$i];
        if ($i + 1 < $length && $normalized[$i + 1] !== $first) {
            $second = $normalized[$i + 1];
            $i += 2;
        } else {
            $second = $first === 'X' ? 'Q' : 'X';
            $i++;
        }
        $result .= $first . $second;
    }
    return $result;
}

function playfair(string $text, string $key, bool $encrypt): string
{
    $board = square($key);
    $input = $encrypt ? preparePlayfair($text) : str_replace('J', 'I', $text);
    $distance = $encrypt ? 1 : 4;
    $result = '';
    for ($i = 0, $length = strlen($input); $i < $length; $i += 2) {
        $a = strpos($board, $input[$i]);
        $b = strpos($board, $input[$i + 1]);
        $ra = intdiv($a, 5);
        $rb = intdiv($b, 5);
        $ca = $a % 5;
        $cb = $b % 5;
        if ($ra === $rb) {
            $ca = ($ca + $distance) % 5;
            $cb = ($cb + $distance) % 5;
        } elseif ($ca === $cb) {
            $ra = ($ra + $distance) % 5;
            $rb = ($rb + $distance) % 5;
        } else {
            [$ca, $cb] = [$cb, $ca];
        }
        $result .= $board[5 * $ra + $ca] . $board[5 * $rb + $cb];
    }
    return $result;
}
