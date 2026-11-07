<?php
declare(strict_types=1);

require_once __DIR__ . '/bitstream.php';

const METHODS = ['PLAIN', 'DICTIONARY', 'RLE', 'DELTA_BINARY_PACKED', 'DELTA_LENGTH_BYTE_ARRAY'];
const TYPES = ['INT', 'STRING', 'BOOL', 'DATE'];
const CANDIDATES = ['INT' => [0, 1, 3], 'STRING' => [0, 1, 4], 'BOOL' => [0, 2], 'DATE' => [0, 1, 3]];

function delta_encode(array $values): string
{
    $result = uleb(128) . uleb(4) . uleb(count($values)) . zigzag($values[0] ?? 0);
    for ($start = 1; $start < count($values); $start += 128) {
        $deltas = [];
        for ($i = $start; $i < min($start + 128, count($values)); ++$i) {
            $deltas[] = $values[$i] - $values[$i - 1];
        }
        $minimum = min($deltas);
        $result .= zigzag($minimum);
        $miniblocks = $widths = [];
        for ($block = 0; $block < 4; ++$block) {
            $adjusted = array_map(static fn(int $value): int => $value - $minimum, array_slice($deltas, 32 * $block, 32));
            $widths[] = $adjusted ? bits(max($adjusted)) : 0;
            $miniblocks[] = $adjusted;
        }
        $result .= implode('', array_map('chr', $widths));
        foreach ($miniblocks as $block => $adjusted) {
            if ($adjusted) {
                $result .= pack_bits(array_pad($adjusted, 32, 0), $widths[$block]);
            }
        }
    }
    return $result;
}

function delta_decode(Reader $reader): array
{
    $reader->uleb();
    $reader->uleb();
    $count = $reader->uleb();
    $first = $reader->zigzag();
    $result = $count ? [$first] : [];
    while (count($result) < $count) {
        $minimum = $reader->zigzag();
        $widths = $reader->take(4);
        for ($block = 0; $block < 4 && count($result) < $count; ++$block) {
            $remaining = min(32, $count - count($result));
            $adjusted = unpack_bits($reader, 32, ord($widths[$block]));
            for ($i = 0; $i < $remaining; ++$i) {
                $result[] = $result[count($result) - 1] + ($minimum + $adjusted[$i]);
            }
        }
    }
    return $result;
}

function encode_values(string $type, int $method, array $values, array $dictionary = [], ?array $ranks = null): string
{
    if ($method === 1) {
        $width = bits(count($dictionary) - 1);
        $ranks ??= array_flip($dictionary);
        return chr($width) . hybrid_encode(array_map(static fn(mixed $value): int => $ranks[$value], $values), $width);
    }
    if ($method === 2) {
        $encoded = hybrid_encode(array_map(static fn(bool $value): int => $value ? 1 : 0, $values), 1);
        return uint32(strlen($encoded)) . $encoded;
    }
    if ($method === 3) {
        return delta_encode($values);
    }
    if ($method === 4) {
        return delta_encode(array_map('strlen', $values)) . implode('', $values);
    }
    if ($type === 'BOOL') {
        $numbers = array_map(static fn(bool $value): int => $value ? 1 : 0, $values);
        return pack_bits(array_pad($numbers, intdiv(count($numbers) + 7, 8) * 8, 0), 1);
    }
    $result = '';
    foreach ($values as $value) {
        $result .= $type === 'STRING' ? uint32(strlen($value)) . $value : signed32($value);
    }
    return $result;
}

function decode_values(string $type, int $method, Reader $reader, int $count, array $dictionary = []): array
{
    if ($method === 1) {
        return array_map(static fn(int $index): mixed => $dictionary[$index], hybrid_decode($reader, $count, $reader->byte()));
    }
    if ($method === 2) {
        $encoded = new Reader($reader->take($reader->uint32()));
        return array_map(static fn(int $value): bool => $value === 1, hybrid_decode($encoded, $count, 1));
    }
    if ($method === 3) {
        return delta_decode($reader);
    }
    if ($method === 4) {
        return array_map(static fn(int $length): string => $reader->text($length), delta_decode($reader));
    }
    if ($type === 'BOOL') {
        return array_map(static fn(int $value): bool => $value === 1,
            array_slice(unpack_bits($reader, intdiv($count + 7, 8) * 8, 1), 0, $count));
    }
    $values = [];
    for ($i = 0; $i < $count; ++$i) {
        $values[] = $type === 'STRING' ? $reader->text($reader->uint32()) : $reader->signed32();
    }
    return $values;
}

function statistic_value(string $type, mixed $value): string
{
    return match ($type) {
        'STRING' => uleb(strlen($value)) . $value,
        'BOOL' => chr($value ? 1 : 0),
        default => zigzag($value)
    };
}

function read_statistic_value(Reader $reader, string $type): mixed
{
    return match ($type) {
        'STRING' => $reader->text($reader->uleb()),
        'BOOL' => $reader->byte() === 1,
        default => $reader->zigzag()
    };
}

function statistics_bytes(string $type, ?object $statistics): string
{
    return $statistics === null ? "\0" : "\1" . statistic_value($type, $statistics->minimum) . statistic_value($type, $statistics->maximum);
}

function read_statistics(Reader $reader, string $type): ?object
{
    return $reader->byte() === 0 ? null
        : (object)['minimum' => read_statistic_value($reader, $type), 'maximum' => read_statistic_value($reader, $type)];
}
