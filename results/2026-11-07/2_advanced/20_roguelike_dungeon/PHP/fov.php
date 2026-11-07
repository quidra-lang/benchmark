<?php
declare(strict_types=1);

namespace Roguelike;

const DIRECTION_NAMES = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
const DIRECTIONS = [[0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1]];
const PASSABLE = ['.' => true, '#' => true, '+' => true, '<' => true, '>' => true];

function passable(Level $level, int $x, int $y): bool { return array_key_exists($level->terrain[$y][$x], PASSABLE); }

function canMove(Level $level, int $x, int $y, int $dx, int $dy): bool
{
    return passable($level, $x + $dx, $y + $dy) && ($dx === 0 || $dy === 0
        || $level->terrain[$y][$x] !== '+' && $level->terrain[$y + $dy][$x + $dx] !== '+');
}

function sightLine(int $x0, int $y0, int $x1, int $y1): array
{
    $dx = abs($x1 - $x0);
    $dy = abs($y1 - $y0);
    $sx = $x1 > $x0 ? 1 : -1;
    $sy = $y1 > $y0 ? 1 : -1;
    $err = $dx - $dy;
    $x = $x0;
    $y = $y0;
    $cells = [];
    while ($x !== $x1 || $y !== $y1) {
        $e2 = 2 * $err;
        if ($e2 > -$dy) {
            $err -= $dy;
            $x += $sx;
        }
        if ($e2 < $dx) {
            $err += $dx;
            $y += $sy;
        }
        $cells[] = [$x, $y];
    }
    return $cells;
}

function fieldOfView(Level $level, int $px, int $py, int $radius): array
{
    $visible = array_fill(0, $level->height, array_fill(0, $level->width, false));
    for ($y = max(0, $py - $radius); $y <= min($level->height - 1, $py + $radius); $y++) {
        for ($x = max(0, $px - $radius); $x <= min($level->width - 1, $px + $radius); $x++) {
            $dx = $x - $px;
            $dy = $y - $py;
            if ($dx * $dx + $dy * $dy > $radius * $radius) {
                continue;
            }
            $cells = sightLine($px, $py, $x, $y);
            $clear = true;
            for ($index = 0; $index + 1 < count($cells); $index++) {
                if (!passable($level, $cells[$index][0], $cells[$index][1])) {
                    $clear = false;
                    break;
                }
            }
            $visible[$y][$x] = $clear;
        }
    }
    return $visible;
}

function distances(Level $level, int $px, int $py): array
{
    $distance = array_fill(0, $level->height, array_fill(0, $level->width, -1));
    $distance[$py][$px] = 0;
    $queue = [[$px, $py]];
    for ($head = 0; $head < count($queue); $head++) {
        [$x, $y] = $queue[$head];
        foreach (DIRECTIONS as [$dx, $dy]) {
            if (canMove($level, $x, $y, $dx, $dy) && $distance[$y + $dy][$x + $dx] === -1) {
                $distance[$y + $dy][$x + $dx] = $distance[$y][$x] + 1;
                $queue[] = [$x + $dx, $y + $dy];
            }
        }
    }
    return $distance;
}
