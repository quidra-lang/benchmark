<?php

function solveQueens(int $n): array
{
    $columns = array_fill(0, $n, -1);
    $first = [];
    $solutions = 0;
    $place = function (int $row) use ($n, &$columns, &$first, &$solutions, &$place): void {
        if ($row === $n) {
            $solutions++;
            if (!$first) {
                $first = $columns;
            }
            return;
        }
        for ($column = 0; $column < $n; $column++) {
            $valid = true;
            for ($previous = 0; $previous < $row; $previous++) {
                if ($columns[$previous] === $column || abs($columns[$previous] - $column) === $row - $previous) {
                    $valid = false;
                    break;
                }
            }
            if ($valid) {
                $columns[$row] = $column;
                $place($row + 1);
            }
        }
    };
    $place(0);
    return [$solutions, $first];
}

$firstEight = [];
for ($n = 4; $n <= 8; $n++) {
    [$solutions, $first] = solveQueens($n);
    printf("N=%d: %d solutions\n", $n, $solutions);
    if ($n === 8) {
        $firstEight = $first;
    }
}
foreach ($firstEight as $column) {
    echo str_repeat('.', $column), 'Q', str_repeat('.', 7 - $column), "\n";
}
