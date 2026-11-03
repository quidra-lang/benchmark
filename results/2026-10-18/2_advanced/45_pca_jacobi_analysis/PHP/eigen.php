<?php

function offDiagonal(array $values): float
{
    $total = 0.0;
    for ($p = 0; $p < count($values) - 1; $p++) {
        for ($q = $p + 1; $q < count($values); $q++) $total += $values[$p][$q] * $values[$p][$q];
    }
    return $total;
}

function jacobiRotate(array &$values, array &$vectors, int $p, int $q): void
{
    if ($values[$p][$q] == 0.0) return;
    $theta = ($values[$q][$q] - $values[$p][$p]) / (2 * $values[$p][$q]);
    $tangent = 1 / (abs($theta) + sqrt($theta * $theta + 1));
    if ($theta < 0) $tangent = -$tangent;
    $cosine = 1 / sqrt($tangent * $tangent + 1);
    $sine = $tangent * $cosine;
    for ($r = 0; $r < count($values); $r++) {
        if ($r === $p || $r === $q) continue;
        $x = $values[$r][$p];
        $y = $values[$r][$q];
        $values[$r][$p] = $values[$p][$r] = $cosine * $x - $sine * $y;
        $values[$r][$q] = $values[$q][$r] = $sine * $x + $cosine * $y;
    }
    $cross = $values[$p][$q];
    $values[$p][$p] -= $tangent * $cross;
    $values[$q][$q] += $tangent * $cross;
    $values[$p][$q] = $values[$q][$p] = 0.0;
    for ($r = 0; $r < count($values); $r++) {
        $x = $vectors[$r][$p];
        $y = $vectors[$r][$q];
        $vectors[$r][$p] = $cosine * $x - $sine * $y;
        $vectors[$r][$q] = $sine * $x + $cosine * $y;
    }
}

function jacobi(array $input): array
{
    $size = count($input);
    $values = matCopy($input);
    $vectors = matIdentity($size);
    $initial = offDiagonal($values);
    $sweeps = 0;
    if ($initial != 0.0) {
        for ($sweep = 1; $sweep <= 100; $sweep++) {
            for ($p = 0; $p < $size - 1; $p++) {
                for ($q = $p + 1; $q < $size; $q++) jacobiRotate($values, $vectors, $p, $q);
            }
            $off = offDiagonal($values);
            if ($sweeps === 0 && $off < 1e-16 * $initial) $sweeps = $sweep;
            if ($off < 1e-22 * $initial) break;
        }
    }
    $order = range(0, $size - 1);
    usort($order, fn($a, $b) => ($values[$b][$b] <=> $values[$a][$a]) ?: ($a <=> $b));
    $resultValues = [];
    $resultVectors = [];
    foreach ($order as $index) {
        $resultValues[] = $values[$index][$index];
        $resultVectors[] = vecOrient(vecNormalize(matColumn($vectors, $index)));
    }
    return ['values' => $resultValues, 'vectors' => $resultVectors, 'sweeps' => $sweeps];
}

function powerIteration(array $input, array $reference): array
{
    $remaining = matCopy($input);
    $results = [];
    for ($component = 0; $component < count($input); $component++) {
        $vector = array_fill(0, count($input), 1.0);
        $agreement = null;
        $target = $reference['vectors'][$component];
        $negative = array_map(fn($value) => -$value, $target);
        for ($iteration = 1; $iteration <= 1000; $iteration++) {
            $vector = vecNormalize(matVector($remaining, $vector));
            $distance = min(vecDifference($vector, $target), vecDifference($vector, $negative));
            if ($agreement === null && $distance < 0.000001) $agreement = $iteration;
        }
        $value = vecDot($vector, matVector($remaining, $vector));
        $oriented = vecOrient(vecNormalize($vector));
        $match = abs($value - $reference['values'][$component]) <= 1e-8 * $reference['values'][0] &&
            vecDifference($oriented, $target) <= 0.000001;
        $results[] = ['value' => $value, 'vector' => $oriented, 'agreement' => $agreement, 'match' => $match];
        matDeflate($remaining, $value, $oriented);
    }
    return $results;
}
