<?php
declare(strict_types=1);

function cholesky(array $matrix, array $free): array
{
    $size = count($matrix);
    $lower = array_fill(0, $size, array_fill(0, $size, 0.0));
    for ($row = 0; $row < $size; ++$row) {
        for ($column = 0; $column <= $row; ++$column) {
            $value = $matrix[$row][$column];
            for ($i = 0; $i < $column; ++$i) {
                $value -= $lower[$row][$i] * $lower[$column][$i];
            }
            if ($column < $row) {
                $lower[$row][$column] = $value / $lower[$column][$column];
            } else {
                if ($value <= 0.000000001 * $matrix[$row][$row]) {
                    return [null, $free[$row]];
                }
                $lower[$row][$row] = sqrt($value);
            }
        }
    }
    return [$lower, null];
}

function solve(array $lower, array $right): array
{
    $size = count($right);
    $intermediate = $result = array_fill(0, $size, 0.0);
    for ($row = 0; $row < $size; ++$row) {
        $value = $right[$row];
        for ($column = 0; $column < $row; ++$column) {
            $value -= $lower[$row][$column] * $intermediate[$column];
        }
        $intermediate[$row] = $value / $lower[$row][$row];
    }
    for ($row = $size - 1; $row >= 0; --$row) {
        $value = $intermediate[$row];
        for ($column = $row + 1; $column < $size; ++$column) {
            $value -= $lower[$column][$row] * $result[$column];
        }
        $result[$row] = $value / $lower[$row][$row];
    }
    return $result;
}
