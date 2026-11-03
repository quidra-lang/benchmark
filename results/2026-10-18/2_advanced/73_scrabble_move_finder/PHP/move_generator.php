<?php

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

function anchors($grid)
{
    $result = [];
    if (!boardTiles($grid)) {
        return [CENTER * BOARD_SIZE + CENTER => true];
    }
    for ($row = 0; $row < BOARD_SIZE; $row++) {
        for ($column = 0; $column < BOARD_SIZE; $column++) {
            if ($grid[$row][$column] === '.' && adjacent($grid, $row, $column)) {
                $result[$row * BOARD_SIZE + $column] = true;
            }
        }
    }
    return $result;
}

function crossChecks($grid, $trie)
{
    $allowed = array_fill(0, BOARD_SIZE, array_fill(0, BOARD_SIZE, null));
    $checked = $dead = $total = 0;
    for ($row = 0; $row < BOARD_SIZE; $row++) {
        for ($column = 0; $column < BOARD_SIZE; $column++) {
            if ($grid[$row][$column] !== '.') {
                continue;
            }
            $letters = [];
            if (!occupied($grid, $row - 1, $column) && !occupied($grid, $row + 1, $column)) {
                foreach (str_split(ALPHABET) as $letter) {
                    $letters[$letter] = true;
                }
            } else {
                $checked++;
                foreach (str_split(ALPHABET) as $letter) {
                    $word = crossWord($grid, ['row' => $row, 'column' => $column, 'letter' => $letter], 'down');
                    if ($trie->has(strtoupper($word['word']))) {
                        $letters[$letter] = true;
                    }
                }
                if (!$letters) {
                    $dead++;
                }
                $total += count($letters);
            }
            $allowed[$row][$column] = $letters;
        }
    }
    return ['allowed' => $allowed, 'stats' => [$checked, $dead, $total]];
}

function acrossMoves($grid, $rack, $trie, $anchorSet, $checks)
{
    $result = [];
    $counts = array_count_values(str_split($rack));
    foreach ($anchorSet as $anchor => $unused) {
        $row = intdiv($anchor, BOARD_SIZE);
        $anchorColumn = $anchor % BOARD_SIZE;
        $choices = function ($node, $allowed, $use) use (&$counts) {
            $letters = array_keys($node->children);
            sort($letters, SORT_STRING);
            foreach ($letters as $letter) {
                if ($allowed !== null && !isset($allowed[$letter])) {
                    continue;
                }
                foreach ([$letter, '?'] as $tile) {
                    if (($counts[$tile] ?? 0) === 0) {
                        continue;
                    }
                    $counts[$tile]--;
                    $use($node->children[$letter], $tile === '?' ? strtolower($letter) : $letter);
                    $counts[$tile]++;
                }
            }
        };
        $extend = function ($column, $node, $word, $start, $filled) use (&$extend, &$result, $grid, $row, $anchorColumn, $checks, $choices) {
            $isOccupied = $column < BOARD_SIZE && $grid[$row][$column] !== '.';
            if (!$isOccupied && $filled && $node->terminal) {
                $tiles = [];
                for ($i = 0; $i < strlen($word); $i++) {
                    if ($grid[$row][$start + $i] === '.') {
                        $tiles[] = ['row' => $row, 'column' => $start + $i, 'letter' => $word[$i]];
                    }
                }
                $result[] = ['row' => $row, 'column' => $start, 'direction' => 'across', 'word' => $word, 'tiles' => $tiles];
            }
            if ($column >= BOARD_SIZE) {
                return;
            }
            if ($isOccupied) {
                $letter = $grid[$row][$column];
                $child = $node->children[strtoupper($letter)] ?? null;
                if ($child !== null) {
                    $extend($column + 1, $child, $word . $letter, $start, $filled);
                }
            } else {
                $choices($node, $checks['allowed'][$row][$column], function ($child, $letter) use (&$extend, $column, $word, $start, $filled, $anchorColumn) {
                    $extend($column + 1, $child, $word . $letter, $start, $filled || $column === $anchorColumn);
                });
            }
        };
        if (occupied($grid, $row, $anchorColumn - 1)) {
            $start = $anchorColumn - 1;
            while (occupied($grid, $row, $start - 1)) {
                $start--;
            }
            $prefix = implode('', array_slice($grid[$row], $start, $anchorColumn - $start));
            $node = $trie->find(strtoupper($prefix));
            if ($node !== null) {
                $extend($anchorColumn, $node, $prefix, $start, false);
            }
        } else {
            $limit = 0;
            while ($anchorColumn - $limit - 1 >= 0 && $grid[$row][$anchorColumn - $limit - 1] === '.' &&
                !isset($anchorSet[$row * BOARD_SIZE + $anchorColumn - $limit - 1])) {
                $limit++;
            }
            $leftPart = function ($node, $word) use (&$leftPart, $extend, $choices, $anchorColumn, $limit) {
                $extend($anchorColumn, $node, $word, $anchorColumn - strlen($word), false);
                if (strlen($word) < $limit) {
                    $choices($node, null, function ($child, $letter) use (&$leftPart, $word) {
                        $leftPart($child, $word . $letter);
                    });
                }
            };
            $leftPart($trie->root, '');
        }
    }
    return $result;
}

function generateMoves($grid, $rack, $trie)
{
    $anchorSet = anchors($grid);
    $across = crossChecks($grid, $trie);
    $transposed = transposeBoard($grid);
    $down = crossChecks($transposed, $trie);
    $moves = acrossMoves($grid, $rack, $trie, $anchorSet, $across);
    foreach (acrossMoves($transposed, $rack, $trie, anchors($transposed), $down) as $move) {
        $tiles = transposeTiles($move['tiles']);
        if (count($tiles) === 1 && (occupied($grid, $tiles[0]['row'], $tiles[0]['column'] - 1) ||
            occupied($grid, $tiles[0]['row'], $tiles[0]['column'] + 1))) {
            continue;
        }
        $moves[] = array_merge($move, ['row' => $move['column'], 'column' => $move['row'], 'direction' => 'down', 'tiles' => $tiles]);
    }
    return ['moves' => $moves, 'anchors' => count($anchorSet), 'across' => $across['stats'], 'down' => $down['stats']];
}
