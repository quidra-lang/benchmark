<?php
namespace LinkAnalysis;

function hits(int $count, array $nodes, array $links, int $iterations): array
{
    $sources = $targets = array_fill(0, $count, []);
    usort($links, fn($a, $b) => ($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1]));
    foreach ($links as [$source, $target]) {
        $sources[$target][] = $source;
        $targets[$source][] = $target;
    }
    $authority = $hub = array_fill(0, $count, 0.0);
    foreach ($nodes as $node) $authority[$node] = $hub[$node] = 1.0;
    for ($step = 0; $step < $iterations; $step++) {
        $incoming = $outgoing = array_fill(0, $count, 0.0);
        foreach ($nodes as $node) foreach ($sources[$node] as $source) $incoming[$node] += $hub[$source];
        foreach ($nodes as $node) foreach ($targets[$node] as $target) $outgoing[$node] += $incoming[$target];
        $anorm = $hnorm = 0.0;
        foreach ($nodes as $node) {
            $anorm += $incoming[$node] * $incoming[$node];
            $hnorm += $outgoing[$node] * $outgoing[$node];
        }
        $anorm = sqrt($anorm);
        $hnorm = sqrt($hnorm);
        foreach ($nodes as $node) {
            $authority[$node] = $incoming[$node] / $anorm;
            $hub[$node] = $outgoing[$node] / $hnorm;
        }
    }
    return [$authority, $hub];
}
