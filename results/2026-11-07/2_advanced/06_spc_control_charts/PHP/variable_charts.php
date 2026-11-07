<?php
function real_sum(array $values): float { $sum = 0.0; foreach ($values as $value) $sum += $value; return $sum; }
function subgroup_statistics(array $values, int $size): array {
    $groups = [];
    foreach (array_chunk($values, $size) as $index => $points) {
        $total = array_sum($points); $squares = array_sum(array_map(fn($x) => $x * $x, $points));
        $groups[$index + 1] = ['number' => $index + 1, 'values' => $points, 'total' => $total, 'mean' => $total / $size, 'range' => max($points) - min($points), 'sd' => sqrt(($size * $squares - $total * $total) / ($size * ($size - 1)))];
    }
    return $groups;
}
function moving_ranges(array $values): array { $ranges = []; for ($i = 1; $i < count($values); $i++) $ranges[] = abs($values[$i] - $values[$i - 1]); return $ranges; }
function outside(float $value, array $limits): bool { return $value < $limits[0] || $value > $limits[2]; }
function variable_limits(string $family, array $points, array $groups, array $values, int $size): array {
    [$a2,$a3,$b3,$b4,$d3,$d4,$d2] = CONTROL_CONSTANTS[$size];
    if ($family === 'I_MR') {
        $measurements = array_map(fn($i) => $values[$i - 1], $points); $ranges = moving_ranges($measurements);
        $mean = array_sum($measurements) / count($measurements); $average = array_sum($ranges) / count($ranges); $width = 3 * $average / CONTROL_CONSTANTS[2][6];
        return [[$mean - $width, $mean, $mean + $width], [CONTROL_CONSTANTS[2][4] * $average, $average, CONTROL_CONSTANTS[2][5] * $average]];
    }
    $selected = array_map(fn($i) => $groups[$i], $points); $mean = array_sum(array_column($selected, 'total')) / (count($points) * $size);
    if ($family === 'XBAR_R') { $average = array_sum(array_column($selected, 'range')) / count($points); return [[$mean - $a2 * $average,$mean,$mean + $a2 * $average],[$d3 * $average,$average,$d4 * $average]]; }
    $average = real_sum(array_column($selected, 'sd')) / count($points); return [[$mean - $a3 * $average,$mean,$mean + $a3 * $average],[$b3 * $average,$average,$b4 * $average]];
}
