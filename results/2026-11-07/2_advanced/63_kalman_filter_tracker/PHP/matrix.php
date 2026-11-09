<?php

function matZeros($rows, $columns = null)
{
    return array_fill(0, $rows, array_fill(0, $columns ?? $rows, 0.0));
}

function matDiagonal($values)
{
    $result = matZeros(count($values));
    foreach ($values as $i => $value) {
        $result[$i][$i] = $value;
    }
    return $result;
}

function matIdentity($size)
{
    return matDiagonal(array_fill(0, $size, 1.0));
}

function matTranspose($matrix)
{
    $result = matZeros(count($matrix[0]), count($matrix));
    foreach ($matrix as $i => $row) {
        foreach ($row as $j => $value) {
            $result[$j][$i] = $value;
        }
    }
    return $result;
}

function matProduct($first, $second)
{
    $result = matZeros(count($first), count($second[0]));
    foreach ($first as $i => $row) {
        for ($j = 0; $j < count($second[0]); $j++) {
            $value = $row[0] * $second[0][$j];
            for ($k = 1; $k < count($row); $k++) {
                $value += $row[$k] * $second[$k][$j];
            }
            $result[$i][$j] = $value;
        }
    }
    return $result;
}

function matVectorProduct($matrix, $vector)
{
    $result = [];
    foreach ($matrix as $row) {
        $value = $row[0] * $vector[0];
        for ($k = 1; $k < count($vector); $k++) {
            $value += $row[$k] * $vector[$k];
        }
        $result[] = $value;
    }
    return $result;
}

function matAdd($first, $second)
{
    foreach ($first as $i => $row) {
        foreach ($row as $j => $value) {
            $first[$i][$j] = $value + $second[$i][$j];
        }
    }
    return $first;
}

function matSubtract($first, $second)
{
    foreach ($first as $i => $row) {
        foreach ($row as $j => $value) {
            $first[$i][$j] = $value - $second[$i][$j];
        }
    }
    return $first;
}

function vecAdd($first, $second)
{
    foreach ($first as $i => $value) {
        $first[$i] = $value + $second[$i];
    }
    return $first;
}

function vecSubtract($first, $second)
{
    foreach ($first as $i => $value) {
        $first[$i] = $value - $second[$i];
    }
    return $first;
}

function matInverse($matrix)
{
    $n = count($matrix);
    $unit = matIdentity($n);
    $rows = [];
    foreach ($matrix as $i => $row) {
        $rows[] = array_merge($row, $unit[$i]);
    }
    for ($c = 0; $c < $n; $c++) {
        $pivot = $rows[$c][$c];
        for ($j = 0; $j < 2 * $n; $j++) {
            $rows[$c][$j] /= $pivot;
        }
        for ($i = 0; $i < $n; $i++) {
            if ($i === $c) {
                continue;
            }
            $factor = $rows[$i][$c];
            for ($j = 0; $j < 2 * $n; $j++) {
                $rows[$i][$j] -= $factor * $rows[$c][$j];
            }
        }
    }
    return array_map(fn($row) => array_slice($row, $n), $rows);
}

function determinant2($matrix)
{
    return $matrix[0][0] * $matrix[1][1] - $matrix[0][1] * $matrix[1][0];
}

function quadratic2($vector, $matrix)
{
    return $vector[0] * ($matrix[0][0] * $vector[0] + $matrix[0][1] * $vector[1]) +
        $vector[1] * ($matrix[1][0] * $vector[0] + $matrix[1][1] * $vector[1]);
}
