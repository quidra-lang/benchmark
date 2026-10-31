<?php

function readImage(string $path): array
{
    $lines = file($path, FILE_IGNORE_NEW_LINES);
    [$width, $height] = array_map('intval', explode(' ', $lines[1]));
    $pixels = [];
    foreach (array_slice($lines, 3) as $line) {
        foreach (explode(' ', $line) as $value) $pixels[] = (int)$value;
    }
    return compact('width', 'height', 'pixels');
}

function readTrig(string $path): array
{
    $cos = $sin = [];
    foreach (file($path, FILE_IGNORE_NEW_LINES) as $line) {
        [$theta, $c, $s] = array_map('intval', explode(' ', $line));
        $cos[$theta] = $c;
        $sin[$theta] = $s;
    }
    return compact('cos', 'sin');
}

function readParams(string $path): array
{
    $params = [];
    foreach (file($path, FILE_IGNORE_NEW_LINES) as $line) {
        $tokens = explode(' ', $line);
        $name = array_shift($tokens);
        $values = array_map('intval', $tokens);
        $params[$name] = $name === 'gauss_kernel' ? $values : $values[0];
    }
    return $params;
}

function writeImage(string $path, int $width, int $height, array $pixels): void
{
    $lines = ['P2', $width . ' ' . $height, '255'];
    for ($y = 0; $y < $height; $y++) $lines[] = implode(' ', array_slice($pixels, $y * $width, $width));
    file_put_contents($path, implode("\n", $lines) . "\n");
}
