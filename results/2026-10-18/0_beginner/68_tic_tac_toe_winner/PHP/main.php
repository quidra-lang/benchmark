<?php

function outcome(array $board): string
{
    $lines = $board;
    for ($column = 0; $column < 3; $column++) {
        $lines[] = $board[0][$column] . $board[1][$column] . $board[2][$column];
    }
    $lines[] = $board[0][0] . $board[1][1] . $board[2][2];
    $lines[] = $board[0][2] . $board[1][1] . $board[2][0];
    foreach ($lines as $line) {
        if ($line[0] !== '.' && $line === str_repeat($line[0], 3)) {
            return $line[0] . ' wins';
        }
    }
    return str_contains(implode('', $board), '.') ? 'in progress' : 'draw';
}

$boards = [
    ['XXX', 'OO.', 'O.X'], ['X.O', '.X.', 'O..'], ['XO.', '.OX', 'XO.'], ['XOX', 'XOO', 'OXX'],
    ['X.O', 'XO.', 'O.X'], ['XOX', 'OXO', 'OXX'],
];
foreach ($boards as $i => $board) {
    printf("board %d: %s\n", $i + 1, outcome($board));
}
