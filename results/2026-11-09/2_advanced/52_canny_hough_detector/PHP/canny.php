<?php

function neighbors(int $index, int $width, int $height): array
{
    $x = $index % $width;
    $y = intdiv($index, $width);
    $result = [];
    for ($dy = -1; $dy <= 1; $dy++) {
        for ($dx = -1; $dx <= 1; $dx++) {
            if ($dx === 0 && $dy === 0) continue;
            $nx = $x + $dx;
            $ny = $y + $dy;
            if ($nx >= 0 && $nx < $width && $ny >= 0 && $ny < $height) $result[] = $ny * $width + $nx;
        }
    }
    return $result;
}

function directions(array $gx, array $gy): array
{
    $result = [];
    foreach ($gx as $index => $value) {
        $ax = abs($value);
        $ay = abs($gy[$index]);
        if (29 * $ay <= 12 * $ax) $result[] = 0;
        elseif (29 * $ay >= 70 * $ax) $result[] = 90;
        else $result[] = $value * $gy[$index] < 0 ? 45 : 135;
    }
    return $result;
}

function suppress(array $magnitude, array $direction, int $width, int $height): array
{
    $result = array_fill(0, $width * $height, 0);
    $offset = [0 => -1, 45 => 1 - $width, 90 => -$width, 135 => -1 - $width];
    for ($y = 1; $y < $height - 1; $y++) {
        for ($x = 1; $x < $width - 1; $x++) {
            $index = $y * $width + $x;
            $delta = $offset[$direction[$index]];
            $m = $magnitude[$index];
            if ($m > $magnitude[$index + $delta] && $m >= $magnitude[$index - $delta]) $result[$index] = $m;
        }
    }
    return $result;
}

function hysteresis(array $nms, int $width, int $height, int $low, int $high): array
{
    $edges = $strong = $weak = array_fill(0, count($nms), 0);
    $queue = [];
    foreach ($nms as $i => $value) {
        if ($value >= $high) {
            $strong[$i] = $edges[$i] = 1;
            $queue[] = $i;
        } elseif ($value >= $low) {
            $weak[$i] = 1;
        }
    }
    for ($head = 0; $head < count($queue); $head++) {
        foreach (neighbors($queue[$head], $width, $height) as $next) {
            if (!$edges[$next] && $nms[$next] >= $low) {
                $edges[$next] = 1;
                $queue[] = $next;
            }
        }
    }
    return compact('edges', 'strong', 'weak');
}

function edgeComponents(array $edges, int $width, int $height): array
{
    $visited = array_fill(0, count($edges), 0);
    $groups = [];
    foreach ($edges as $index => $value) {
        if (!$value || $visited[$index]) continue;
        $group = [$index];
        $visited[$index] = 1;
        for ($head = 0; $head < count($group); $head++) {
            foreach (neighbors($group[$head], $width, $height) as $next) {
                if ($edges[$next] && !$visited[$next]) {
                    $visited[$next] = 1;
                    $group[] = $next;
                }
            }
        }
        $groups[] = $group;
    }
    return $groups;
}
