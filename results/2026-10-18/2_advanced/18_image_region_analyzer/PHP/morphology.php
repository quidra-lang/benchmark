<?php
declare(strict_types=1);

namespace ImageRegions;

const NEIGHBORHOOD = [[0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1]];

function pixelKey(int $x, int $y): string
{
    return $x . ',' . $y;
}

function occupied(array $mask, int $x, int $y): bool
{
    return $y >= 0 && $y < count($mask) && $x >= 0 && $x < count($mask[$y]) && $mask[$y][$x];
}

function erode(array $mask, array $offsets): array
{
    $result = [];
    foreach ($mask as $y => $sourceRow) {
        $row = [];
        foreach ($sourceRow as $x => $_) {
            $foreground = true;
            foreach ($offsets as [$dx, $dy]) {
                if (!occupied($mask, $x + $dx, $y + $dy)) {
                    $foreground = false;
                    break;
                }
            }
            $row[] = $foreground;
        }
        $result[] = $row;
    }
    return $result;
}

function dilate(array $mask, array $offsets): array
{
    $result = [];
    foreach ($mask as $y => $sourceRow) {
        $row = [];
        foreach ($sourceRow as $x => $_) {
            $foreground = false;
            foreach ($offsets as [$dx, $dy]) {
                if (occupied($mask, $x - $dx, $y - $dy)) {
                    $foreground = true;
                    break;
                }
            }
            $row[] = $foreground;
        }
        $result[] = $row;
    }
    return $result;
}

function opening(array $mask, array $offsets): array
{
    return dilate(erode($mask, $offsets), $offsets);
}

function closing(array $mask, array $offsets): array
{
    return erode(dilate($mask, $offsets), $offsets);
}

function neighborBits(array $pixels, int $x, int $y): array
{
    $bits = [];
    foreach (NEIGHBORHOOD as [$dx, $dy]) {
        $bits[] = isset($pixels[pixelKey($x + $dx, $y + $dy)]);
    }
    return $bits;
}

function transitions(array $bits): int
{
    $count = 0;
    for ($index = 0; $index < 8; $index++) {
        if (!$bits[$index] && $bits[($index + 1) % 8]) {
            $count++;
        }
    }
    return $count;
}

function crossingNumber(array $pixels, int $x, int $y): int
{
    return transitions(neighborBits($pixels, $x, $y));
}

function removable(array $bits, bool $firstStep): bool
{
    $count = array_sum($bits);
    if ($count < 2 || $count > 6 || transitions($bits) !== 1) {
        return false;
    }
    [$p2, $p4, $p6, $p8] = [$bits[0], $bits[2], $bits[4], $bits[6]];
    if ($firstStep) {
        return !($p2 && $p4 && $p6) && !($p4 && $p6 && $p8);
    }
    return !($p2 && $p4 && $p8) && !($p2 && $p6 && $p8);
}

function thinningStep(array &$skeleton, bool $firstStep): bool
{
    $removed = [];
    foreach ($skeleton as $key => [$x, $y]) {
        if (removable(neighborBits($skeleton, $x, $y), $firstStep)) {
            $removed[] = $key;
        }
    }
    foreach ($removed as $key) {
        unset($skeleton[$key]);
    }
    return $removed !== [];
}

function thin(array $pixels): array
{
    $skeleton = [];
    foreach ($pixels as [$x, $y]) {
        $skeleton[pixelKey($x, $y)] = [$x, $y];
    }
    while (true) {
        $first = thinningStep($skeleton, true);
        $second = thinningStep($skeleton, false);
        if (!$first && !$second) {
            return $skeleton;
        }
    }
}
