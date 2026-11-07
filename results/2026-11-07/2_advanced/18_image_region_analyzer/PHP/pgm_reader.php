<?php
declare(strict_types=1);

namespace ImageRegions;

final class Image
{
    public function __construct(
        public string $name,
        public int $width,
        public int $height,
        public int $maxval,
        public array $pixels
    ) {}
}

function readImages(string $path): array
{
    $words = [];
    foreach (file($path, FILE_IGNORE_NEW_LINES) as $line) {
        $line = trim(explode('#', $line, 2)[0]);
        if ($line !== '') {
            array_push($words, ...preg_split('/ +/', $line));
        }
    }
    $images = [];
    $position = 0;
    while ($position < count($words)) {
        $name = $words[$position + 1];
        $width = (int)$words[$position + 3];
        $height = (int)$words[$position + 4];
        $maxval = (int)$words[$position + 5];
        $position += 6;
        $pixels = [];
        for ($y = 0; $y < $height; $y++) {
            $row = [];
            for ($x = 0; $x < $width; $x++) {
                $row[] = (int)$words[$position++];
            }
            $pixels[] = $row;
        }
        $images[] = new Image($name, $width, $height, $maxval, $pixels);
    }
    return $images;
}
