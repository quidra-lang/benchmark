<?php

function readLines(string $path): array { return file($path, FILE_IGNORE_NEW_LINES); }
function writeLines(string $path, array $lines): void { file_put_contents($path, implode("\n", $lines) . "\n"); }

function readPPM(string $path): object
{
    $lines = readLines($path);
    [$width, $height] = array_map('intval', explode(' ', $lines[1]));
    $pixels = [];
    foreach (array_slice($lines, 3) as $line) {
        $values = array_map('intval', explode(' ', $line));
        $row = [];
        for ($x = 0; $x < $width; $x++) $row[] = array_slice($values, 3 * $x, 3);
        $pixels[] = $row;
    }
    return (object) compact('width', 'height', 'pixels');
}

function writePPM(string $path, object $image): void
{
    $lines = ['P3', $image->width . ' ' . $image->height, '255'];
    foreach ($image->pixels as $row) {
        $values = [];
        foreach ($row as $pixel) foreach ($pixel as $value) $values[] = $value;
        $lines[] = implode(' ', $values);
    }
    writeLines($path, $lines);
}

function readParams(string $path): object
{
    $result = (object) [];
    foreach (readLines($path) as $line) {
        $values = explode(' ', $line);
        $name = array_shift($values);
        $result->$name = $name === 'huffman' || $name === 'sampling' ? $values[0]
            : ($name === 'qualities' || $name === 'truncate' ? array_map('intval', $values) : (int) $values[0]);
    }
    return $result;
}

function readTables(string $path): object
{
    $lines = readLines($path);
    $rows = function (int $start) use ($lines): array {
        $values = [];
        foreach (array_slice($lines, $start, 8) as $line) foreach (explode(' ', $line) as $value) $values[] = (int) $value;
        return $values;
    };
    $huffman = [];
    for ($i = 27; $i < 39; $i += 3) {
        [, $tableClass, $id] = explode(' ', $lines[$i]);
        $huffman[] = (object) ['tableClass' => (int) $tableClass, 'id' => (int) $id,
            'bits' => array_map('intval', explode(' ', $lines[$i + 1])), 'values' => array_map('intval', explode(' ', $lines[$i + 2]))];
    }
    return (object) ['C' => $rows(1), 'base' => [$rows(10), $rows(19)], 'huffman' => $huffman];
}

function readHex(string $path): array
{
    $text = implode('', readLines($path));
    $bytes = [];
    for ($i = 0; $i < strlen($text); $i += 2) $bytes[] = hexdec(substr($text, $i, 2));
    return $bytes;
}

function writeHex(string $path, array $bytes): void
{
    $lines = [];
    foreach (array_chunk($bytes, 32) as $chunk) {
        $line = '';
        foreach ($chunk as $value) $line .= str_pad(dechex($value), 2, '0', STR_PAD_LEFT);
        $lines[] = $line;
    }
    writeLines($path, $lines);
}
