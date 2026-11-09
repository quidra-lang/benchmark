<?php

namespace Tiles;

const SUITS = 'mpsz';

const WINDS = 'ESWN';

const YAOCHUU = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33];

const GREEN = [19, 20, 21, 23, 25, 32];

function parse(string $text, bool $empty = false): ?array
{
    if ($text === '-')
        return $empty ? [] : null;
    $result = $digits = [];
    foreach (str_split($text) as $ch) {
        if ($ch >= '0' && $ch <= '9')
            $digits[] = (int) $ch;
        elseif (($suit = strpos(SUITS, $ch)) !== false && $digits) {
            foreach ($digits as $digit) {
                if ($suit === 3 && ($digit < 1 || $digit > 7))
                    return null;
                $result[] = ['kind' => ($suit * 9) + ($digit === 0 ? 5 : $digit) - 1, 'red' => $digit === 0];
            }
            $digits = [];
        } else
            return null;
    }
    return $result && !$digits ? $result : null;
}

function name(int $kind): string
{
    return (($kind % 9) + 1) . SUITS[intdiv($kind, 9)];
}

function block(array $kinds): string
{
    sort($kinds, SORT_NUMERIC);
    return implode('', array_map(fn($k) => ($k % 9) + 1, $kinds)) . SUITS[intdiv($kinds[0], 9)];
}

function counts(array $tiles): array
{
    $counts = array_fill(0, 34, 0);
    foreach ($tiles as $tile)
        ++$counts[$tile['kind']];
    return $counts;
}

function honor(int $kind): bool
{
    return $kind >= 27;
}

function terminal(int $kind): bool
{
    return $kind < 27 && (($kind % 9) === 0 || ($kind % 9) === 8);
}

function yaochuu(int $kind): bool
{
    return honor($kind) || terminal($kind);
}

function wind(string $wind): int
{
    return 27 + strpos(WINDS, $wind);
}

function nextDora(int $kind): int
{
    if ($kind < 27)
        return (intdiv($kind, 9) * 9) + ((($kind % 9) + 1) % 9);
    if ($kind < 31)
        return 27 + (($kind - 26) % 4);
    return 31 + (($kind - 30) % 3);
}
