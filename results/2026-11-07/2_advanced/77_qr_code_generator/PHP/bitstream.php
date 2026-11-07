<?php

const ALPHANUMERIC = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';

function appendBits(array &$bits, int $value, int $width): void
{
    for ($bit = $width - 1; $bit >= 0; $bit--) {
        $bits[] = ($value >> $bit) & 1;
    }
}

function fromCodewords(array $codewords): array
{
    $bits = [];
    foreach ($codewords as $value) {
        appendBits($bits, $value, 8);
    }
    return $bits;
}

function toCodewords(array $bits): array
{
    $codewords = [];
    for ($i = 0; $i < count($bits); $i += 8) {
        $value = 0;
        for ($j = 0; $j < 8; $j++) {
            $value = ($value << 1) | $bits[$i + $j];
        }
        $codewords[] = $value;
    }
    return $codewords;
}

class BitReader
{
    private array $bits;
    public int $position = 0;

    public function __construct(array $bits)
    {
        $this->bits = $bits;
    }

    public function remaining(): int
    {
        return count($this->bits) - $this->position;
    }

    public function read(int $width): int
    {
        $value = 0;
        for ($i = 0; $i < $width; $i++) {
            $value = ($value << 1) | $this->bits[$this->position++];
        }
        return $value;
    }
}

function binary(int $value, int $width): string
{
    return str_pad(decbin($value), $width, '0', STR_PAD_LEFT);
}
