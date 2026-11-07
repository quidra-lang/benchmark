<?php

function readPlate(): object
{
    $lines = file('input/plate.txt', FILE_IGNORE_NEW_LINES);
    [$width, $height, $dx, $depth] = explode(' ', $lines[0]);
    $width = (int) $width;
    $height = (int) $height;
    $codes = str_split(implode('', array_slice($lines, 1)));
    $neighbors = [];
    for ($r = 0; $r < $height; $r++) for ($c = 0; $c < $width; $c++) {
        $p = $r * $width + $c;
        $neighbors[] = [$c > 0 ? $p - 1 : -1, $c + 1 < $width ? $p + 1 : -1,
            $r > 0 ? $p - $width : -1, $r + 1 < $height ? $p + $width : -1];
    }
    return (object) ['width' => $width, 'height' => $height, 'dx' => (float) $dx, 'depth' => (float) $depth,
        'count' => $width * $height, 'codes' => $codes, 'neighbors' => $neighbors];
}

function segmentCells(object $mesh, string $edge, int $start, int $end): array
{
    $cells = [];
    for ($i = $start; $i <= $end; $i++) {
        if ($edge === 'top') $cells[] = $i;
        elseif ($edge === 'bottom') $cells[] = ($mesh->height - 1) * $mesh->width + $i;
        elseif ($edge === 'left') $cells[] = $i * $mesh->width;
        else $cells[] = $i * $mesh->width + $mesh->width - 1;
    }
    return $cells;
}

function sourceCells(object $mesh, int $r1, int $c1, int $r2, int $c2): array
{
    $cells = [];
    for ($r = $r1; $r <= $r2; $r++) for ($c = $c1; $c <= $c2; $c++) $cells[] = $r * $mesh->width + $c;
    return $cells;
}
