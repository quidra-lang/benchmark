<?php

function renderGrid(
    array $polygons,
    ?array $operands,
    int $x0,
    int $y0,
    int $cw,
    int $ch,
    int $cols,
    int $rows,
): array {
    $rings = [];
    foreach ($polygons as $polygon)
        array_push($rings, ...$polygon);
    $counts = array_fill_keys(['#', 'a', 'b', '+'], 0);
    $lines = [];
    for ($row = 0; $row < $rows; ++$row) {
        $text = '';
        for ($col = 0; $col < $cols; ++$col) {
            $p = new Point(
                (2 * $x0) + (((2 * $col) + 1) * $cw),
                (2 * $y0) + (((2 * ($rows - 1 - $row)) + 1) * $ch),
                2,
            );
            if (interior($rings, $p))
                $character = '#';
            elseif ($operands !== null) {
                $a = interior($operands[0]->rings, $p);
                $b = interior($operands[1]->rings, $p);
                $character = $a && $b ? '+' : ($a ? 'a' : ($b ? 'b' : '.'));
            } else
                $character = '.';
            $text .= $character;
            if (isset($counts[$character]))
                ++$counts[$character];
        }
        $lines[] = $text;
    }
    return [$lines, $counts];
}
