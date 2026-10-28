<?php

const LARGE_GLYPHS = [
    '\\sum' => ['\\--', ' > ', '/--'],
    '\\prod' => ['___', '| |', '| |'],
    '\\int' => [' /', ' |', '/ '],
];

function symbolType(string $symbol): string
{
    if (str_contains('+-*', $symbol))
        return 'binary';
    if (str_contains('=<>:', $symbol))
        return 'relation';
    if (str_contains('([', $symbol))
        return 'open';
    if (str_contains(')]!', $symbol))
        return 'close';
    if (str_contains(',;', $symbol))
        return 'punctuation';
    return 'ordinary';
}

final class Box
{
    public array $children = [], $strings = [];

    public function __construct(
        public int $width,
        public int $height,
        public int $baseline,
        public string $description,
    ) {}

    public function descent(): int
    {
        return $this->height - 1 - $this->baseline;
    }

    public function add(self $child, int $x, int $y, string $role = ''): void
    {
        $this->children[] = [$child, $x, $y, $role];
    }

    public function draw(string $text, int $x = 0, int $y = 0): void
    {
        $this->strings[] = [$text, $x, $y];
    }
}

function delimiterGlyph(string $delimiter, int $height): array
{
    if ($delimiter === '.')
        return [];
    $character = substr($delimiter, -1);
    if ($height === 1)
        return [$character];
    if (in_array($delimiter, ['[', ']', '|'], true))
        return array_fill(0, $height, $delimiter);
    $left = $delimiter === '(' || $delimiter === '\\{';
    $glyph = [$left ? '/' : '\\', ...array_fill(0, $height - 2, '|'), $left ? '\\' : '/'];
    if (($delimiter === '\\{' || $delimiter === '\\}') && $height >= 3)
        $glyph[intdiv($height - 1, 2)] = $left ? '<' : '>';
    return $glyph;
}
