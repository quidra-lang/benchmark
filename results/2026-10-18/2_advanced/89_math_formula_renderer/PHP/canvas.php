<?php

function walkBox(Box $box, int $x, int $y, int $level = 0, string $role = ''): Generator
{
    yield [$box, $x, $y, $level, $role];
    foreach ($box->children as [$child, $dx, $dy, $childRole])
        yield from walkBox($child, $x + $dx, $y + $dy, $level + 1, $childRole);
}

function drawBoxes(array $roots, int $width, int $height): array
{
    $grid = array_fill(0, $height, str_repeat(' ', $width));
    foreach ($roots as [$root, $rx, $ry])
        foreach (walkBox($root, $rx, $ry) as [$box, $x, $y])
            foreach ($box->strings as [$text, $dx, $dy])
                for ($i = 0; $i < strlen($text); ++$i)
                    if ($text[$i] !== ' ')
                        $grid[$y + $dy][$x + $dx + $i] = $text[$i];
    return array_map(fn($line) => rtrim($line, ' '), $grid);
}

function boxLines(array $roots): array
{
    $entries = [];
    foreach ($roots as [$root, $rx, $ry])
        foreach (walkBox($root, $rx, $ry) as [$box, $x, $y, $level, $role])
            $entries[] = [
                str_repeat('  ', $level)
                    . $role
                    . $box->description
                    . " x=$x y=$y w={$box->width} h={$box->height} b={$box->baseline}",
                $level,
                explode(' ', $box->description, 2)[0],
            ];
    return $entries;
}
