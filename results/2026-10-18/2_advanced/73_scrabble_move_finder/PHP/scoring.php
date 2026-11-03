<?php

const RACK_SIZE = 7;
const BINGO = 50;

function tileKind($letter)
{
    return $letter >= 'a' && $letter <= 'z' ? '?' : $letter;
}

function moveSquares($move)
{
    $result = [];
    foreach (str_split($move['word']) as $i => $letter) {
        $result[] = ['row' => $move['row'] + ($move['direction'] === 'down' ? $i : 0),
            'column' => $move['column'] + ($move['direction'] === 'across' ? $i : 0), 'letter' => $letter];
    }
    return $result;
}

function crossWord($grid, $tile, $direction)
{
    $dr = $direction === 'down' ? 1 : 0;
    $dc = $direction === 'across' ? 1 : 0;
    $row = $tile['row'];
    $column = $tile['column'];
    while (occupied($grid, $row - $dr, $column - $dc)) {
        $row -= $dr;
        $column -= $dc;
    }
    $start = ['row' => $row, 'column' => $column, 'direction' => $direction];
    $word = '';
    while (inside($row, $column) && (($row === $tile['row'] && $column === $tile['column']) || occupied($grid, $row, $column))) {
        $word .= (($row === $tile['row'] && $column === $tile['column']) ? $tile['letter'] : $grid[$row][$column]);
        $row += $dr;
        $column += $dc;
    }
    $start['word'] = $word;
    return $start;
}

function wordScore($grid, $word, $table)
{
    $total = 0;
    $multiplier = 1;
    foreach (moveSquares($word) as $tile) {
        $points = $table[tileKind($tile['letter'])]['value'];
        if ($grid[$tile['row']][$tile['column']] === '.') {
            $premium = premium($tile['row'], $tile['column']);
            if ($premium === '+') {
                $points *= 2;
            } elseif ($premium === '^') {
                $points *= 3;
            } elseif ($premium === '*') {
                $multiplier *= 2;
            } elseif ($premium === '#') {
                $multiplier *= 3;
            }
        }
        $total += $points;
    }
    return $total * $multiplier;
}

function scoreMove($grid, $move, $table)
{
    $tiles = array_values(array_filter(moveSquares($move), fn($tile) => $grid[$tile['row']][$tile['column']] === '.'));
    $words = [['row' => $move['row'], 'column' => $move['column'], 'direction' => $move['direction'], 'word' => $move['word']]];
    $perpendicular = $move['direction'] === 'across' ? 'down' : 'across';
    foreach ($tiles as $tile) {
        $cross = crossWord($grid, $tile, $perpendicular);
        if (strlen($cross['word']) >= 2) {
            $words[] = $cross;
        }
    }
    $total = count($tiles) === RACK_SIZE ? BINGO : 0;
    foreach ($words as &$word) {
        $word['score'] = wordScore($grid, $word, $table);
        $total += $word['score'];
    }
    unset($word);
    return array_merge($move, ['tiles' => $tiles, 'words' => $words, 'score' => $total]);
}
