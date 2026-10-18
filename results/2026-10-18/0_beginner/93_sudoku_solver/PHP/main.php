<?php
$puzzle = ['800025000','070080005','260400070','000001900','010000040','600200000','900010000','700000004','020000036'];
$board = array_map(fn($row) => array_map('intval',str_split($row)),$puzzle);
$placements = 0;
function valid(array $board, int $row, int $column, int $digit): bool {
    for ($i = 0; $i < 9; $i++) {
        if ($board[$row][$i] === $digit || $board[$i][$column] === $digit) return false;
    }
    $blockRow = intdiv($row,3)*3;
    $blockColumn = intdiv($column,3)*3;
    for ($r = $blockRow; $r < $blockRow+3; $r++) {
        for ($c = $blockColumn; $c < $blockColumn+3; $c++) {
            if ($board[$r][$c] === $digit) return false;
        }
    }
    return true;
}
function solve(array &$board, int &$placements): bool {
    for ($row = 0; $row < 9; $row++) {
        for ($column = 0; $column < 9; $column++) {
            if ($board[$row][$column] === 0) {
                for ($digit = 1; $digit <= 9; $digit++) {
                    if (valid($board,$row,$column,$digit)) {
                        $board[$row][$column] = $digit;
                        $placements++;
                        if (solve($board,$placements)) return true;
                        $board[$row][$column] = 0;
                    }
                }
                return false;
            }
        }
    }
    return true;
}
solve($board,$placements);
foreach ($board as $row) echo implode(' ',$row), "\n";
printf("placements: %d\n",$placements);
