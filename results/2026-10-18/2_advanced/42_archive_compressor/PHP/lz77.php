<?php

function lz77Tokens(string $data, int $offsetBits, int $lengthBits): array
{
    $size = strlen($data);
    $window = 1 << $offsetBits;
    $lookahead = (1 << $lengthBits) + 2;
    $previous = array_fill(0, $size, -1);
    $latest = [];
    for ($i = 0; $i + 2 < $size; $i++) {
        $key = "\0" . substr($data, $i, 3);
        $previous[$i] = $latest[$key] ?? -1;
        $latest[$key] = $i;
    }
    $tokens = [];
    $position = 0;
    while ($position < $size) {
        $maximum = min($lookahead, $size - $position);
        $bestLength = 2;
        $bestDistance = 0;
        $candidate = $maximum >= 3 ? $previous[$position] : -1;
        while ($candidate >= 0 && $position - $candidate <= $window) {
            $distance = $position - $candidate;
            $length = 3;
            while ($length < $maximum && $data[$position + $length] === $data[$position + $length - $distance]) {
                $length++;
            }
            if ($length > $bestLength) {
                $bestLength = $length;
                $bestDistance = $distance;
            }
            if ($length === $maximum) {
                break;
            }
            $candidate = $previous[$candidate];
        }
        if ($bestDistance > 0) {
            $tokens[] = ['distance' => $bestDistance, 'length' => $bestLength];
            $position += $bestLength;
        } else {
            $tokens[] = ['literal' => ord($data[$position++])];
        }
    }
    return $tokens;
}

function lz77CopyMatch(string &$output, int $distance, int $length, int $originalLength): void
{
    if ($distance > strlen($output)) {
        throw new DecodingError('bad_offset');
    }
    if (strlen($output) + $length > $originalLength) {
        throw new DecodingError('overrun');
    }
    for ($i = 0; $i < $length; $i++) {
        $output .= $output[strlen($output) - $distance];
    }
}
