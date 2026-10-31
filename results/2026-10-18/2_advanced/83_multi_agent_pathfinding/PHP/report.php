<?php

function agentName(int $i): string
{
    return chr(65 + $i);
}

function cellText(int $cell, Grid $grid): string
{
    return ($cell % $grid->width) . ',' . intdiv($cell, $grid->width);
}

function actionString(array $path, Grid $grid): string
{
    $actions = [0 => '.', -$grid->width => 'N', 1 => 'E', $grid->width => 'S', -1 => 'W'];
    $text = '';
    for ($i = 1; $i < count($path); ++$i)
        $text .= $actions[$path[$i] - $path[$i - 1]];
    return $text;
}

function conflictText(array $c, Grid $grid): string
{
    $names = agentName($c['a']) . ' ' . agentName($c['b']);
    return $c['kind'] === 'vertex'
        ? "vertex t {$c['time']} $names at " . cellText($c['cell'], $grid)
        : "edge t {$c['time']} $names from " . cellText($c['u'], $grid) . ' to ' . cellText($c['v'], $grid);
}

function fraction(int $a, int $b): string
{
    $x = $a;
    $y = $b;
    while ($y) {
        [$x, $y] = [$y, $x % $y];
    }
    return intdiv($a, $x) . '/' . intdiv($b, $x);
}

function picture(Grid $grid, array $placements): array
{
    $rows = $grid->rows;
    foreach ($placements as $cell => $ch)
        $rows[intdiv($cell, $grid->width)][$cell % $grid->width] = $ch;
    return $rows;
}

function saveFile(string $name, array $lines): void
{
    if (!is_dir('output'))
        mkdir('output');
    file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}
