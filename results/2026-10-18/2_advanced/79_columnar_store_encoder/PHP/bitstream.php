<?php
declare(strict_types=1);

function bits(int $value): int
{
    $width = 0;
    while ($value > 0) {
        ++$width;
        $value = intdiv($value, 2);
    }
    return $width;
}

function uleb(int $value): string
{
    $result = '';
    while ($value >= 128) {
        $result .= chr($value % 128 + 128);
        $value = intdiv($value, 128);
    }
    return $result . chr($value);
}

function zigzag(int $value): string
{
    return uleb($value >= 0 ? 2 * $value : -2 * $value - 1);
}

function uint32(int $value): string
{
    return pack('V', $value);
}

function signed32(int $value): string
{
    return uint32($value < 0 ? $value + 4294967296 : $value);
}

final class Reader
{
    public function __construct(public string $bytes, public int $position = 0) {}

    public function byte(): int
    {
        return ord($this->bytes[$this->position++]);
    }

    public function take(int $count): string
    {
        $result = substr($this->bytes, $this->position, $count);
        $this->position += $count;
        return $result;
    }

    public function text(int $count): string
    {
        return $this->take($count);
    }

    public function uleb(): int
    {
        $result = 0;
        $scale = 1;
        do {
            $byte = $this->byte();
            $result += ($byte % 128) * $scale;
            $scale *= 128;
        } while ($byte >= 128);
        return $result;
    }

    public function zigzag(): int
    {
        $value = $this->uleb();
        return $value % 2 === 0 ? intdiv($value, 2) : -intdiv($value + 1, 2);
    }

    public function uint32(): int
    {
        return unpack('V', $this->take(4))[1];
    }

    public function signed32(): int
    {
        $value = $this->uint32();
        return $value >= 2147483648 ? $value - 4294967296 : $value;
    }
}

function pack_bits(array $values, int $width): string
{
    $bytes = array_fill(0, intdiv(count($values) * $width, 8), 0);
    foreach ($values as $index => $value) {
        for ($bit = 0; $bit < $width; ++$bit) {
            $serial = $index * $width + $bit;
            $bytes[intdiv($serial, 8)] += ($value % 2) * (1 << ($serial % 8));
            $value = intdiv($value, 2);
        }
    }
    return implode('', array_map('chr', $bytes));
}

function unpack_bits(Reader $reader, int $count, int $width): array
{
    $bytes = $reader->take(intdiv($count * $width, 8));
    $result = array_fill(0, $count, 0);
    for ($index = 0; $index < $count; ++$index) {
        for ($bit = 0; $bit < $width; ++$bit) {
            $serial = $index * $width + $bit;
            $value = intdiv(ord($bytes[intdiv($serial, 8)]), 1 << ($serial % 8)) % 2;
            $result[$index] += $value * (1 << $bit);
        }
    }
    return $result;
}

function hybrid_encode(array $values, int $width): string
{
    $result = '';
    $run_length = static function (int $start) use ($values): int {
        $end = $start + 1;
        while ($end < count($values) && $values[$end] === $values[$start]) {
            ++$end;
        }
        return $end - $start;
    };
    $index = 0;
    while ($index < count($values)) {
        $length = $run_length($index);
        if ($length >= 8) {
            $result .= uleb(2 * $length);
            $value = $values[$index];
            for ($byte = 0; $byte < intdiv($width + 7, 8); ++$byte) {
                $result .= chr($value % 256);
                $value = intdiv($value, 256);
            }
            $index += $length;
        } else {
            $end = $index;
            $groups = 0;
            do {
                $end += 8;
                ++$groups;
            } while ($end < count($values) && $groups < 63 && $run_length($end) < 8);
            $packed = array_pad(array_slice($values, $index, $end - $index), 8 * $groups, 0);
            $result .= uleb(2 * $groups + 1) . pack_bits($packed, $width);
            $index = $end;
        }
    }
    return $result;
}

function hybrid_decode(Reader $reader, int $count, int $width): array
{
    $result = [];
    while (count($result) < $count) {
        $header = $reader->uleb();
        if ($header % 2 === 0) {
            $value = 0;
            $scale = 1;
            for ($byte = 0; $byte < intdiv($width + 7, 8); ++$byte) {
                $value += $reader->byte() * $scale;
                $scale *= 256;
            }
            array_push($result, ...array_fill(0, intdiv($header, 2), $value));
        } else {
            array_push($result, ...unpack_bits($reader, 8 * intdiv($header - 1, 2), $width));
        }
    }
    return array_slice($result, 0, $count);
}

function adler32(string $bytes): int
{
    $a = 1;
    $b = 0;
    for ($i = 0; $i < strlen($bytes); ++$i) {
        $a = ($a + ord($bytes[$i])) % 65521;
        $b = ($b + $a) % 65521;
    }
    return $b * 65536 + $a;
}
