<?php
declare(strict_types=1);

const RELOCATION_TYPES = ['ABS32', 'REL32', 'ABS16', 'HI16', 'LO16', 'GPREL16', 'CALL24'];
const RELOCATION_SPECS = [
    'ABS32' => [4, -2147483648, 4294967296], 'REL32' => [4, -2147483648, 2147483648],
    'ABS16' => [2, -32768, 65536], 'HI16' => [2, -2147483648, 4294967296],
    'LO16' => [2, null, null], 'GPREL16' => [2, -32768, 32768], 'CALL24' => [3, -33554432, 33554432]
];

function modulo(int $value, int $divisor): int
{
    return (($value % $divisor) + $divisor) % $divisor;
}

function in_range(string $type, int $value): bool
{
    [, $lower, $upper] = RELOCATION_SPECS[$type];
    return $lower === null || ($lower <= $value && $value < $upper);
}

function calculate(string $type, int $symbol, int $addend, int $position, int $gp): array
{
    $value = $symbol + $addend;
    if ($type === 'REL32' || $type === 'CALL24') {
        $value -= $position;
    } elseif ($type === 'GPREL16') {
        $value -= $gp;
    }
    $width = RELOCATION_SPECS[$type][0];
    $field = match ($type) {
        'HI16' => modulo(intdiv(modulo($value, 4294967296) + 32768, 65536), 65536),
        'CALL24' => modulo(intdiv($value, 4), 16777216),
        default => modulo($value, 1 << (8 * $width))
    };
    return ['value' => $value, 'field' => $field, 'width' => $width, 'overflow' => !in_range($type, $value)];
}

function is_unpaired(array $relocations, int $index): bool
{
    $current = $relocations[$index];
    if ($current->type !== 'HI16') {
        return false;
    }
    $next = $relocations[$index + 1] ?? null;
    return $next === null || $next->type !== 'LO16' || $next->symbol !== $current->symbol || $next->addend !== $current->addend;
}

function little_endian(int $value, int $width): string
{
    $data = '';
    for ($index = 0; $index < $width; ++$index) {
        $data .= chr(modulo($value, 256));
        $value = intdiv($value, 256);
    }
    return $data;
}
