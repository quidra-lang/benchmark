<?php

const TIDE_PI = 3.141592653589793;

function angle($speed, $time) {
    $degrees = $speed * $time;
    $reduced = $degrees - 360 * floor($degrees / 360);
    return $reduced * TIDE_PI / 180;
}

function regressors($constituents, $time) {
    $values = [1.0];
    foreach ($constituents as $constituent) {
        $theta = angle($constituent->speed, $time);
        $values[] = cos($theta);
        $values[] = sin($theta);
    }
    return $values;
}

function normalEquations($rows, $constituents) {
    $size = 2 * count($constituents) + 1;
    $matrix = array_fill(0, $size, array_fill(0, $size, 0.0));
    $rhs = array_fill(0, $size, 0.0);
    foreach ($rows as $row) {
        $x = regressors($constituents, $row->time);
        for ($i = 0; $i < $size; $i++) {
            for ($j = 0; $j < $size; $j++) $matrix[$i][$j] += $x[$i] * $x[$j];
            $rhs[$i] += $x[$i] * $row->value;
        }
    }
    return compact('matrix', 'rhs');
}

function solveEquations($matrix, $rhs) {
    $size = count($rhs);
    $augmented = [];
    foreach ($matrix as $i => $row) {
        $identity = [];
        for ($j = 0; $j < $size; $j++) $identity[] = $i === $j ? 1.0 : 0.0;
        $augmented[] = array_merge($row, [$rhs[$i]], $identity);
    }
    for ($column = 0; $column < $size; $column++) {
        $pivot = $column;
        for ($row = $column + 1; $row < $size; $row++) if (abs($augmented[$row][$column]) > abs($augmented[$pivot][$column])) $pivot = $row;
        if ($pivot !== $column) [$augmented[$pivot], $augmented[$column]] = [$augmented[$column], $augmented[$pivot]];
        for ($row = $column + 1; $row < $size; $row++) {
            $factor = $augmented[$row][$column] / $augmented[$column][$column];
            for ($c = $column; $c <= 2 * $size; $c++) $augmented[$row][$c] = $augmented[$row][$c] - $factor * $augmented[$column][$c];
        }
    }
    $coefficients = [];
    $inverse = array_fill(0, $size, array_fill(0, $size, 0.0));
    for ($column = $size; $column <= 2 * $size; $column++) {
        $solution = array_fill(0, $size, 0.0);
        for ($row = $size - 1; $row >= 0; $row--) {
            $value = $augmented[$row][$column];
            for ($j = $row + 1; $j < $size; $j++) $value = $value - $augmented[$row][$j] * $solution[$j];
            $solution[$row] = $value / $augmented[$row][$row];
        }
        if ($column === $size) $coefficients = $solution;
        else for ($row = 0; $row < $size; $row++) $inverse[$row][$column - $size - 1] = $solution[$row];
    }
    return compact('coefficients', 'inverse');
}

function fitHarmonics($rows, $constituents) {
    $equations = normalEquations($rows, $constituents);
    $result = solveEquations($equations['matrix'], $equations['rhs']);
    $coefficients = $result['coefficients'];
    $fitted = [];
    foreach ($constituents as $index => $original) {
        $item = clone $original;
        $item->a = $coefficients[2 * $index + 1];
        $item->b = $coefficients[2 * $index + 2];
        $item->amplitude = sqrt($item->a * $item->a + $item->b * $item->b);
        $item->phase = atan2($item->b, $item->a) * 180 / TIDE_PI;
        if ($item->phase < 0) $item->phase += 360;
        $fitted[] = $item;
    }
    return (object)['mean' => $coefficients[0], 'unknowns' => count($coefficients), 'coefficients' => $coefficients,
        'inverse' => $result['inverse'], 'constituents' => $fitted];
}
