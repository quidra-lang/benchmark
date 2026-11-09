<?php

function position(array $path, int $time): int
{
    return $path[min($time, count($path) - 1)];
}

function conflicts(array $paths): array
{
    $result = [];
    $horizon = max(array_map(fn($p) => count($p) - 1, $paths));
    $n = count($paths);
    for ($t = 1; $t <= $horizon; ++$t)
        for ($a = 0; $a < $n; ++$a)
            for ($b = $a + 1; $b < $n; ++$b) {
                $ca = position($paths[$a], $t);
                $cb = position($paths[$b], $t);
                if ($ca === $cb)
                    $result[] = ['kind' => 'vertex', 'time' => $t, 'a' => $a, 'b' => $b, 'cell' => $ca];
                elseif ($ca === position($paths[$b], $t - 1) && $cb === position($paths[$a], $t - 1))
                    $result[] = [
                        'kind' => 'edge',
                        'time' => $t,
                        'a' => $a,
                        'b' => $b,
                        'u' => position($paths[$a], $t - 1),
                        'v' => $ca,
                    ];
            }
    return $result;
}

function splitConstraints(array $c): array
{
    if ($c['kind'] === 'vertex')
        return [[$c['a'], 'vertex', $c['cell'], $c['time']], [$c['b'], 'vertex', $c['cell'], $c['time']]];
    return [
        [$c['a'], 'edge', [$c['u'], $c['v']], $c['time']],
        [$c['b'], 'edge', [$c['v'], $c['u']], $c['time']],
    ];
}

function planCost(array $paths, string $function): int
{
    $lengths = array_map(fn($p) => count($p) - 1, $paths);
    return $function === 'SOC' ? array_sum($lengths) : max($lengths);
}

function newNode(
    array $paths,
    array $constraints,
    int $number,
    int $depth,
    ?int $parent,
    string $function,
): array {
    return [
        'paths' => $paths,
        'constraints' => $constraints,
        'number' => $number,
        'depth' => $depth,
        'parent' => $parent,
        'conflicts' => conflicts($paths),
        'cost' => planCost($paths, $function),
    ];
}

function nodePriority(array $n): array
{
    return [-$n['cost'], -count($n['conflicts']), -$n['number']];
}

function orderedConstraints(array $node, Grid $grid): array
{
    $rows = [];
    foreach ($node['constraints'] as $agent => $p) {
        foreach ($p->states as $time => $cells)
            foreach ($cells as $cell => $unused)
                $rows[] = [$agent, $time, 0, $cell, $cell, 'vertex'];
        foreach ($p->moves as $time => $moves)
            foreach ($moves as [$u, $v])
                $rows[] = [$agent, $time, 1, $u, $v, 'edge'];
    }
    $key = fn($r) => [
        $r[0],
        $r[1],
        $r[2],
        $r[3] % $grid->width,
        intdiv($r[3], $grid->width),
        $r[4] % $grid->width,
        intdiv($r[4], $grid->width),
    ];
    usort($rows, fn($a, $b) => $key($a) <=> $key($b));
    return $rows;
}
