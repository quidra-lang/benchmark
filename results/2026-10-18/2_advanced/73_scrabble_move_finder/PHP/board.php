<?php

const BOARD_SIZE = 15;
const CENTER = 7;
const PREMIUM_ROWS = [
    '# . . + . . . # . . . + . . #',
    '. * . . . ^ . . . ^ . . . * .',
    '. . * . . . + . + . . . * . .',
    '+ . . * . . . + . . . * . . +',
    '. . . . * . . . . . * . . . .',
    '. ^ . . . ^ . . . ^ . . . ^ .',
    '. . + . . . + . + . . . + . .',
    '# . . + . . . * . . . + . . #',
    '. . + . . . + . + . . . + . .',
    '. ^ . . . ^ . . . ^ . . . ^ .',
    '. . . . * . . . . . * . . . .',
    '+ . . * . . . + . . . * . . +',
    '. . * . . . + . + . . . * . .',
    '. * . . . ^ . . . ^ . . . * .',
    '# . . + . . . # . . . + . . #'
];

function premium($row, $column)
{
    return PREMIUM_ROWS[$row][2 * $column];
}

function inside($row, $column)
{
    return $row >= 0 && $row < BOARD_SIZE && $column >= 0 && $column < BOARD_SIZE;
}

function occupied($grid, $row, $column)
{
    return inside($row, $column) && $grid[$row][$column] !== '.';
}

function squareName($row, $column)
{
    return chr(65 + $column) . ($row + 1);
}

function position($row, $column, $direction)
{
    return $direction === 'across' ? ($row + 1) . chr(65 + $column) : squareName($row, $column);
}

function emptyBoard()
{
    return array_fill(0, BOARD_SIZE, array_fill(0, BOARD_SIZE, '.'));
}

function transposeBoard($grid)
{
    $result = emptyBoard();
    for ($row = 0; $row < BOARD_SIZE; $row++) {
        for ($column = 0; $column < BOARD_SIZE; $column++) {
            $result[$row][$column] = $grid[$column][$row];
        }
    }
    return $result;
}

function transposeTiles($tiles)
{
    return array_map(fn($tile) => ['row' => $tile['column'], 'column' => $tile['row'], 'letter' => $tile['letter']], $tiles);
}

function parsePosition($text)
{
    if (preg_match('/^([1-9]|1[0-5])([A-O])$/D', $text, $match)) {
        return ['row' => (int)$match[1] - 1, 'column' => ord($match[2]) - 65, 'direction' => 'across'];
    }
    if (preg_match('/^([A-O])([1-9]|1[0-5])$/D', $text, $match)) {
        return ['row' => (int)$match[2] - 1, 'column' => ord($match[1]) - 65, 'direction' => 'down'];
    }
    return null;
}

function boardTiles($grid)
{
    $result = [];
    for ($row = 0; $row < BOARD_SIZE; $row++) {
        for ($column = 0; $column < BOARD_SIZE; $column++) {
            if ($grid[$row][$column] !== '.') {
                $result[] = ['row' => $row, 'column' => $column, 'letter' => $grid[$row][$column]];
            }
        }
    }
    return $result;
}

function adjacent($grid, $row, $column)
{
    foreach ([[-1, 0], [1, 0], [0, -1], [0, 1]] as [$dr, $dc]) {
        if (occupied($grid, $row + $dr, $column + $dc)) {
            return true;
        }
    }
    return false;
}

function connected($grid)
{
    $placed = boardTiles($grid);
    if (!$placed) {
        return true;
    }
    $queue = [$placed[0]];
    $seen = [$placed[0]['row'] * BOARD_SIZE + $placed[0]['column'] => true];
    for ($i = 0; $i < count($queue); $i++) {
        $row = $queue[$i]['row'];
        $column = $queue[$i]['column'];
        foreach ([[-1, 0], [1, 0], [0, -1], [0, 1]] as [$dr, $dc]) {
            $r = $row + $dr;
            $c = $column + $dc;
            $key = $r * BOARD_SIZE + $c;
            if (occupied($grid, $r, $c) && !isset($seen[$key])) {
                $seen[$key] = true;
                $queue[] = ['row' => $r, 'column' => $c];
            }
        }
    }
    return count($seen) === count($placed);
}

function boardWords($grid)
{
    $result = [];
    foreach (['across', 'down'] as $direction) {
        $oriented = $direction === 'across' ? $grid : transposeBoard($grid);
        for ($row = 0; $row < BOARD_SIZE; $row++) {
            $column = 0;
            while ($column < BOARD_SIZE) {
                if ($oriented[$row][$column] === '.') {
                    $column++;
                    continue;
                }
                $start = $column;
                $word = '';
                while ($column < BOARD_SIZE && $oriented[$row][$column] !== '.') {
                    $word .= $oriented[$row][$column++];
                }
                if (strlen($word) >= 2) {
                    $result[] = $direction === 'across' ? ['row' => $row, 'column' => $start, 'direction' => $direction, 'word' => $word] :
                        ['row' => $start, 'column' => $row, 'direction' => $direction, 'word' => $word];
                }
            }
        }
    }
    return $result;
}

function displayBoard($grid)
{
    $lines = ['   ' . implode(' ', str_split('ABCDEFGHIJKLMNO'))];
    for ($row = 0; $row < BOARD_SIZE; $row++) {
        $characters = [];
        for ($column = 0; $column < BOARD_SIZE; $column++) {
            $characters[] = $grid[$row][$column] === '.' ? premium($row, $column) : $grid[$row][$column];
        }
        $lines[] = str_pad((string)($row + 1), 2, ' ', STR_PAD_LEFT) . ' ' . implode(' ', $characters);
    }
    return $lines;
}
