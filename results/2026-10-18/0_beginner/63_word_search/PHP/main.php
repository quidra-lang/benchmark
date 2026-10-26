<?php

$board = [
    'MMONKENBIR',
    'PMTIGERJPL',
    'TGREJEDUZI',
    'SPYUTEJDEC',
    'WKAPSIDLBN',
    'KUVNGSBPRO',
    'RIBSDACBAM',
    'YWVAUAPKAH',
    'KYCGTHHESR',
    'OCCALAOKKR',
];

function findWord(array $board, string $word): string
{
    $directions = [
        ['E', 0, 1], ['SE', 1, 1], ['S', 1, 0], ['SW', 1, -1], ['W', 0, -1], ['NW', -1, -1],
        ['N', -1, 0], ['NE', -1, 1],
    ];
    for ($row = 0; $row < 10; $row++) {
        for ($column = 0; $column < 10; $column++) {
            foreach ($directions as [$name, $dr, $dc]) {
                $matched = true;
                for ($offset = 0; $offset < strlen($word); $offset++) {
                    $r = $row + $offset * $dr;
                    $c = $column + $offset * $dc;
                    if ($r < 0 || $r >= 10 || $c < 0 || $c >= 10 || $board[$r][$c] !== $word[$offset]) {
                        $matched = false;
                        break;
                    }
                }
                if ($matched) {
                    return sprintf('(%d, %d) %s', $row, $column, $name);
                }
            }
        }
    }
    return 'not found';
}

foreach (['TIGER', 'ZEBRA', 'MONKEY', 'PANDA', 'KOALA', 'RABBIT'] as $word) {
    printf("%s: %s\n", $word, findWord($board, $word));
}
