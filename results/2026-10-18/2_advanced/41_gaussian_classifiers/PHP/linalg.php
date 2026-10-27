<?php

function la_matrix($size)
{
    return array_fill(0, $size, array_fill(0, $size, 0.0));
}

function la_cholesky($input)
{
    $size = count($input);
    $lower = la_matrix($size);
    for ($row = 0; $row < $size; $row++) {
        for ($column = 0; $column <= $row; $column++) {
            $total = 0.0;
            for ($k = 0; $k < $column; $k++) $total += $lower[$row][$k] * $lower[$column][$k];
            $value = $input[$row][$column] - $total;
            $lower[$row][$column] = $row === $column ? sqrt($value) : $value / $lower[$column][$column];
        }
    }
    return $lower;
}

function la_forward($lower, $right)
{
    $size = count($right);
    $result = array_fill(0, $size, 0.0);
    for ($row = 0; $row < $size; $row++) {
        $total = 0.0;
        for ($column = 0; $column < $row; $column++) $total += $lower[$row][$column] * $result[$column];
        $result[$row] = ($right[$row] - $total) / $lower[$row][$row];
    }
    return $result;
}

function la_backward($lower, $right)
{
    $size = count($right);
    $result = array_fill(0, $size, 0.0);
    for ($row = $size - 1; $row >= 0; $row--) {
        $total = 0.0;
        for ($column = $row + 1; $column < $size; $column++) $total += $lower[$column][$row] * $result[$column];
        $result[$row] = ($right[$row] - $total) / $lower[$row][$row];
    }
    return $result;
}

function la_log_determinant($lower)
{
    $total = 0.0;
    foreach ($lower as $i => $row) $total += log($row[$i]);
    return 2 * $total;
}

function la_quadratic($lower, $right)
{
    $total = 0.0;
    foreach (la_forward($lower, $right) as $value) $total += $value * $value;
    return $total;
}

function la_jacobi($input)
{
    $size = count($input);
    $current = $input;
    $vectors = la_matrix($size);
    for ($i = 0; $i < $size; $i++) $vectors[$i][$i] = 1.0;
    $sweeps = 0;
    while (true) {
        $total = 0.0;
        for ($a = 0; $a < $size - 1; $a++) {
            for ($b = $a + 1; $b < $size; $b++) $total += $current[$a][$b] * $current[$a][$b];
        }
        if (sqrt($total) < 0.000000000001 || $sweeps === 50) break;
        for ($a = 0; $a < $size - 1; $a++) {
            for ($b = $a + 1; $b < $size; $b++) {
                if ($current[$a][$b] == 0) continue;
                $theta = ($current[$b][$b] - $current[$a][$a]) / (2 * $current[$a][$b]);
                $t = ($theta >= 0 ? 1 : -1) / (abs($theta) + sqrt($theta * $theta + 1));
                $co = 1 / sqrt($t * $t + 1);
                $si = $t * $co;
                for ($k = 0; $k < $size; $k++) {
                    if ($k === $a || $k === $b) continue;
                    $x = $current[$k][$a];
                    $y = $current[$k][$b];
                    $current[$k][$a] = $current[$a][$k] = $co * $x - $si * $y;
                    $current[$k][$b] = $current[$b][$k] = $si * $x + $co * $y;
                }
                $cross = $current[$a][$b];
                $current[$a][$a] -= $t * $cross;
                $current[$b][$b] += $t * $cross;
                $current[$a][$b] = $current[$b][$a] = 0.0;
                for ($k = 0; $k < $size; $k++) {
                    $x = $vectors[$k][$a];
                    $y = $vectors[$k][$b];
                    $vectors[$k][$a] = $co * $x - $si * $y;
                    $vectors[$k][$b] = $si * $x + $co * $y;
                }
            }
        }
        $sweeps++;
    }
    $values = [];
    foreach ($current as $i => $row) $values[] = $row[$i];
    return compact('values', 'vectors', 'sweeps');
}
