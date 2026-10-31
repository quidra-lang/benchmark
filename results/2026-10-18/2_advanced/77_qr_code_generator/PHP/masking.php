<?php

function maskCondition(int $mask, int $x, int $y): bool
{
    switch ($mask) {
        case 0: return ($x + $y) % 2 === 0;
        case 1: return $y % 2 === 0;
        case 2: return $x % 3 === 0;
        case 3: return ($x + $y) % 3 === 0;
        case 4: return (intdiv($y, 2) + intdiv($x, 3)) % 2 === 0;
        case 5: return ($x * $y) % 2 + ($x * $y) % 3 === 0;
        case 6: return (($x * $y) % 2 + ($x * $y) % 3) % 2 === 0;
        case 7: return (($x + $y) % 2 + ($x * $y) % 3) % 2 === 0;
    }
    return false;
}

function applyMask(array $grid, array $areas, int $mask): array
{
    foreach ($grid as $y => $row) {
        foreach ($row as $x => $value) {
            if ($areas[$y][$x] === 'data' && maskCondition($mask, $x, $y)) {
                $grid[$y][$x] = $value ^ 1;
            }
        }
    }
    return $grid;
}

function penalties(array $grid): object
{
    $size = count($grid);
    $n1 = 0;
    $n2 = 0;
    $n3 = 0;
    $dark = 0;
    $examine = function (array $values) use (&$n1, &$n3, $size): void {
        $length = 1;
        for ($i = 1; $i <= $size; $i++) {
            if ($i < $size && $values[$i] === $values[$i - 1]) {
                $length++;
            } else {
                if ($length >= 5) {
                    $n1 += $length - 2;
                }
                $length = 1;
            }
        }
        $text = implode('', $values);
        for ($i = 0; $i + 11 <= $size; $i++) {
            $pattern = substr($text, $i, 11);
            if ($pattern === '10111010000' || $pattern === '00001011101') {
                $n3 += 40;
            }
        }
    };
    for ($y = 0; $y < $size; $y++) {
        $examine($grid[$y]);
        $column = [];
        for ($x = 0; $x < $size; $x++) {
            $column[] = $grid[$x][$y];
            $dark += $grid[$y][$x];
            if ($x + 1 < $size && $y + 1 < $size && $grid[$y][$x] === $grid[$y][$x + 1]
                && $grid[$y][$x] === $grid[$y + 1][$x] && $grid[$y][$x] === $grid[$y + 1][$x + 1]) {
                $n2 += 3;
            }
        }
        $examine($column);
    }
    $n4 = 10 * intdiv(abs(20 * $dark - 10 * $size * $size), $size * $size);
    return (object) ['n1' => $n1, 'n2' => $n2, 'n3' => $n3, 'n4' => $n4, 'total' => $n1 + $n2 + $n3 + $n4, 'dark' => $dark];
}
