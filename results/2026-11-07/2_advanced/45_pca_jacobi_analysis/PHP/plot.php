<?php

function plotGrid(int $width, int $height): array
{
    return array_fill(0, $height, array_fill(0, $width, ' '));
}

function plotFrame(array $grid): array
{
    $border = '+' . str_repeat('-', count($grid[0])) . '+';
    $lines = [$border];
    foreach ($grid as $row) $lines[] = '|' . implode('', $row) . '|';
    $lines[] = $border;
    return $lines;
}

function biplotCell(float $x, float $y, float $maximumX, float $maximumY, int $width, int $height): array
{
    return ['column' => min((int)floor(($x + $maximumX) / (2 * $maximumX) * $width), $width - 1),
        'row' => min((int)floor(($maximumY - $y) / (2 * $maximumY) * $height), $height - 1)];
}

function diagnosticCell(float $t2, float $spe, float $maximumX, float $maximumY, int $width, int $height): array
{
    return ['column' => min((int)floor($t2 / $maximumX * $width), $width - 1),
        'row' => $height - 1 - min((int)floor($spe / $maximumY * $height), $height - 1)];
}

function plotShaft(array $origin, array $tip): array
{
    $dc = $tip['column'] - $origin['column'];
    $dr = $tip['row'] - $origin['row'];
    $steps = max(abs($dc), abs($dr));
    $character = 2 * abs($dr) <= abs($dc) ? '-' : (2 * abs($dc) <= abs($dr) ? '|' : ($dc * $dr < 0 ? '/' : '\\'));
    $cells = [];
    for ($step = 1; $step < $steps; $step++) {
        $cells[] = ['column' => $origin['column'] + ($dc <=> 0) * intdiv(2 * $step * abs($dc) + $steps, 2 * $steps),
            'row' => $origin['row'] + ($dr <=> 0) * intdiv(2 * $step * abs($dr) + $steps, 2 * $steps), 'character' => $character];
    }
    return $cells;
}

function screeBar(int $width, int $bar, int $broken, int $kaiser): string
{
    $line = '';
    for ($position = 1; $position <= $width; $position++) {
        $line .= $position === $broken ? 'o' : ($position === $kaiser ? ':' : ($position <= $bar ? '#' : ' '));
    }
    return $line;
}
