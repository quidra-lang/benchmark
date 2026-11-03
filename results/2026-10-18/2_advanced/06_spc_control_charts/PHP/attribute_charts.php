<?php
const ATTRIBUTE_CHARTS = ['p','np','c','u'];
function center_line(string $chart, array $lots): array {
    $defectives = array_sum(array_column($lots, 2)); $defects = array_sum(array_column($lots, 3)); $inspected = array_sum(array_column($lots, 1));
    $fraction = $defectives / $inspected;
    $value = match ($chart) { 'p' => $fraction, 'np' => $defectives / count($lots), 'c' => $defects / count($lots), default => $defects / $inspected };
    return [$value, $fraction];
}
function lot_point(string $chart, array $lot, array $center): array {
    [$cl,$fraction] = $center; [, $inspected,$defectives,$defects] = $lot;
    [$value,$sigma] = match ($chart) { 'p' => [$defectives / $inspected,sqrt($cl * (1 - $cl) / $inspected)], 'np' => [$defectives,sqrt($cl * (1 - $fraction))], 'c' => [$defects,sqrt($cl)], default => [$defects / $inspected,sqrt($cl / $inspected)] };
    $lcl = max(0.0,$cl - 3 * $sigma); $ucl = $cl + 3 * $sigma;
    return ['value' => $value,'lcl' => $lcl,'ucl' => $ucl,'z' => ($value - $cl) / $sigma,'status' => $value > $ucl ? 'high' : ($value < $lcl ? 'low' : 'ok')];
}
