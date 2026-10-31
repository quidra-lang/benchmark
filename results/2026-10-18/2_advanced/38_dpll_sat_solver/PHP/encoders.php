<?php

function queens(int $size): object
{
    $variables = $size * $size;
    $clauses = [];
    for ($row = 0; $row < $size; $row++) {
        $clause = [];
        for ($column = 0; $column < $size; $column++) $clause[] = $row * $size + $column + 1;
        $clauses[] = $clause;
    }
    for ($first = 1; $first <= $variables; $first++) {
        $row = intdiv($first - 1, $size);
        $column = ($first - 1) % $size;
        for ($second = $first + 1; $second <= $variables; $second++) {
            $otherRow = intdiv($second - 1, $size);
            $otherColumn = ($second - 1) % $size;
            if ($row === $otherRow || $column === $otherColumn || abs($row - $otherRow) === abs($column - $otherColumn)) $clauses[] = [-$first, -$second];
        }
    }
    return (object) compact('variables', 'clauses');
}

function pigeon(int $pigeons, int $holes): object
{
    $clauses = [];
    $variable = fn($pigeon, $hole) => ($pigeon - 1) * $holes + $hole;
    for ($pigeon = 1; $pigeon <= $pigeons; $pigeon++) {
        $clause = [];
        for ($hole = 1; $hole <= $holes; $hole++) $clause[] = $variable($pigeon, $hole);
        $clauses[] = $clause;
    }
    for ($pigeon = 1; $pigeon <= $pigeons; $pigeon++) {
        for ($first = 1; $first <= $holes; $first++) {
            for ($second = $first + 1; $second <= $holes; $second++) $clauses[] = [-$variable($pigeon, $first), -$variable($pigeon, $second)];
        }
    }
    for ($hole = 1; $hole <= $holes; $hole++) {
        for ($first = 1; $first <= $pigeons; $first++) {
            for ($second = $first + 1; $second <= $pigeons; $second++) $clauses[] = [-$variable($first, $hole), -$variable($second, $hole)];
        }
    }
    return (object) ['variables' => $pigeons * $holes, 'clauses' => $clauses];
}

function coloring(object $graph, int $colors): object
{
    $clauses = [];
    $variable = fn($vertex, $color) => ($vertex - 1) * $colors + $color;
    for ($vertex = 1; $vertex <= $graph->vertices; $vertex++) {
        $clause = [];
        for ($color = 1; $color <= $colors; $color++) $clause[] = $variable($vertex, $color);
        $clauses[] = $clause;
    }
    for ($vertex = 1; $vertex <= $graph->vertices; $vertex++) {
        for ($first = 1; $first <= $colors; $first++) {
            for ($second = $first + 1; $second <= $colors; $second++) $clauses[] = [-$variable($vertex, $first), -$variable($vertex, $second)];
        }
    }
    foreach ($graph->edges as [$first, $second]) {
        for ($color = 1; $color <= $colors; $color++) $clauses[] = [-$variable($first, $color), -$variable($second, $color)];
    }
    return (object) ['variables' => $graph->vertices * $colors, 'clauses' => $clauses];
}

function positions(array $model, int $rows, int $width): array
{
    $result = [];
    for ($row = 0; $row < $rows; $row++) {
        for ($column = 1; $column <= $width; $column++) {
            if ($model[$row * $width + $column]) {
                $result[] = $column;
                break;
            }
        }
    }
    return $result;
}
