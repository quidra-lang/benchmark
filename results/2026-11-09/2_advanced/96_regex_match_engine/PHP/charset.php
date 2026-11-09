<?php
declare(strict_types=1);

function digit(?int $code): bool
{
    return $code !== null && $code >= 48 && $code <= 57;
}

function letter(?int $code): bool
{
    return $code !== null && (($code >= 65 && $code <= 90) || ($code >= 97 && $code <= 122));
}

function word(?int $code): bool
{
    return letter($code) || digit($code) || $code === 95;
}

function swap_case(int $code): int
{
    return $code >= 65 && $code <= 90 ? $code + 32 : $code - 32;
}

function complement(array $set): array
{
    return array_diff_key(array_fill(0, 128, true), $set);
}

function shorthand(string $character): array
{
    $lower = strtolower($character);
    $set = [];
    for ($code = 0; $code < 128; ++$code) {
        $present = match ($lower) {
            'd' => digit($code),
            'w' => word($code),
            default => in_array($code, [9, 10, 11, 12, 13, 32], true)
        };
        if ($present) {
            $set[$code] = true;
        }
    }
    return ['set' => $set, 'negated' => $character !== $lower];
}

function same(int $first, int $second, string $flags): bool
{
    return $first === $second || (str_contains($flags, 'i') && letter($first) && swap_case($first) === $second);
}

function class_matches(array $set, bool $negated, int $code, string $flags): bool
{
    $present = isset($set[$code]) || (str_contains($flags, 'i') && letter($code) && isset($set[swap_case($code)]));
    return $present !== $negated;
}

function consumes(array $instruction, string $text, int $position, string $flags): bool
{
    if ($position >= strlen($text)) {
        return false;
    }
    $code = ord($text[$position]);
    return match ($instruction['op']) {
        'CHAR' => same($code, $instruction['character'], $flags),
        'ANY' => str_contains($flags, 's') || $code !== 10,
        default => class_matches($instruction['set'], $instruction['negated'], $code, $flags)
    };
}

function assertion(string $kind, string $text, int $position, string $flags): bool
{
    if ($kind === 'BOL') {
        return $position === 0 || (str_contains($flags, 'm') && $text[$position - 1] === "\n");
    }
    if ($kind === 'EOL') {
        return $position === strlen($text) || (str_contains($flags, 'm') && $text[$position] === "\n");
    }
    $before = $position > 0 && word(ord($text[$position - 1]));
    $after = $position < strlen($text) && word(ord($text[$position]));
    return $kind === 'WORD' ? $before !== $after : $before === $after;
}
