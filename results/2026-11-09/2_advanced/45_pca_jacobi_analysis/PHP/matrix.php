<?php

function matZeros(int $rows, ?int $columns = null): array
{
    return array_fill(0, $rows, array_fill(0, $columns ?? $rows, 0.0));
}

function matIdentity(int $size): array
{
    $result = matZeros($size);
    for ($i = 0; $i < $size; $i++) $result[$i][$i] = 1.0;
    return $result;
}

function matCopy(array $matrix): array
{
    return array_map(fn($row) => array_values($row), $matrix);
}

function matColumn(array $matrix, int $index): array
{
    return array_map(fn($row) => $row[$index], $matrix);
}

function vecDot(array $first, array $second): float
{
    $total = 0.0;
    for ($i = 0; $i < count($first); $i++) $total += $first[$i] * $second[$i];
    return $total;
}

function matVector(array $matrix, array $vector): array
{
    return array_map(fn($row) => vecDot($row, $vector), $matrix);
}

function vecLength(array $vector): float
{
    return sqrt(vecDot($vector, $vector));
}

function vecNormalize(array $vector): array
{
    $length = vecLength($vector);
    return array_map(fn($value) => $value / $length, $vector);
}

function vecOrient(array $vector): array
{
    $largest = 0;
    for ($i = 1; $i < count($vector); $i++) if (abs($vector[$i]) > abs($vector[$largest])) $largest = $i;
    return $vector[$largest] < 0 ? array_map(fn($value) => -$value, $vector) : $vector;
}

function vecDifference(array $first, array $second): float
{
    $maximum = 0.0;
    for ($i = 0; $i < count($first); $i++) $maximum = max($maximum, abs($first[$i] - $second[$i]));
    return $maximum;
}

function matDeflate(array &$matrix, float $value, array $vector): void
{
    for ($i = 0; $i < count($matrix); $i++) {
        for ($j = 0; $j < count($matrix); $j++) $matrix[$i][$j] -= $value * $vector[$i] * $vector[$j];
    }
}

function inverseDeterminant(array $matrix): array
{
    $size = count($matrix);
    $unit = matIdentity($size);
    $augmented = [];
    foreach ($matrix as $i => $row) $augmented[] = array_merge($row, $unit[$i]);
    $determinant = 1.0;
    for ($k = 0; $k < $size; $k++) {
        $pivot = $augmented[$k][$k];
        $determinant *= $pivot;
        for ($j = 0; $j < 2 * $size; $j++) $augmented[$k][$j] /= $pivot;
        for ($i = 0; $i < $size; $i++) {
            if ($i === $k) continue;
            $coefficient = $augmented[$i][$k];
            for ($j = 0; $j < 2 * $size; $j++) $augmented[$i][$j] -= $coefficient * $augmented[$k][$j];
        }
    }
    return ['inverse' => array_map(fn($row) => array_slice($row, $size), $augmented), 'determinant' => $determinant];
}
