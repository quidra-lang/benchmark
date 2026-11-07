<?php
namespace LinkAnalysis;

function power_iteration(array $inEdges, array $teleport, float $damping, int $iterations, float $tolerance): array
{
    $count = count($inEdges);
    $outWeight = array_fill(0, $count, 0);
    foreach ($inEdges as $edges) foreach ($edges as [$source, $weight]) $outWeight[$source] += $weight;
    $selected = array_fill(0, $count, false);
    foreach ($teleport as $node) $selected[$node] = true;
    $size = count($teleport);
    $values = array_map(fn($inSet) => $inSet ? 1 / $size : 0.0, $selected);
    $changes = [];
    $converged = null;
    for ($step = 1; $step <= $iterations; $step++) {
        $dangling = 0.0;
        foreach ($outWeight as $node => $weight) if ($weight === 0) $dangling += $values[$node];
        $base = ((1 - $damping) + $damping * $dangling) / $size;
        $updated = [];
        foreach ($inEdges as $node => $edges) {
            $inflow = 0.0;
            foreach ($edges as [$source, $weight]) $inflow += $values[$source] * $weight / $outWeight[$source];
            $updated[] = $damping * $inflow + ($selected[$node] ? $base : 0.0);
        }
        $change = 0.0;
        foreach ($values as $node => $value) $change += abs($updated[$node] - $value);
        $changes[] = $change;
        $values = $updated;
        if ($converged === null && $change < $tolerance) $converged = $step;
    }
    return ['values' => $values, 'changes' => $changes, 'converged' => $converged];
}
