<?php

$text = [
    '#############',
    '#S..#.......#',
    '#.#.#.###.#.#',
    '#.#...#...#.#',
    '#.###.#.###.#',
    '#...#...#...#',
    '###.#####.#.#',
    '#.......#..G#',
    '#############',
];
$maze = array_map('str_split', $text);
$start = $goal = [];
foreach ($maze as $row => $values) {
    foreach ($values as $column => $c) {
        if ($c === 'S') {
            $start = [$row, $column];
        }
        if ($c === 'G') {
            $goal = [$row, $column];
        }
    }
}
$key = fn($cell) => $cell[0] . ',' . $cell[1];
$queue = [$start];
$parents = [$key($start) => $start];
$head = 0;
while ($head < count($queue)) {
    $cell = $queue[$head++];
    if ($cell === $goal) {
        break;
    }
    foreach ([[-1, 0], [1, 0], [0, -1], [0, 1]] as [$dr, $dc]) {
        $r = $cell[0] + $dr;
        $c = $cell[1] + $dc;
        $next = [$r, $c];
        if ($r >= 0 && $r < 9 && $c >= 0 && $c < 13 && $maze[$r][$c] !== '#' && !isset($parents[$key($next)])) {
            $parents[$key($next)] = $cell;
            $queue[] = $next;
        }
    }
}
$cell = $goal;
$steps = 0;
while ($cell !== $start) {
    [$r, $c] = $cell;
    if ($maze[$r][$c] === '.') {
        $maze[$r][$c] = '*';
    }
    $cell = $parents[$key($cell)];
    $steps++;
}
printf("steps: %d\n", $steps);
foreach ($maze as $row) {
    echo implode('', $row), "\n";
}
