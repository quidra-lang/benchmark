<?php

function dbscan(array $neighborhoods, int $minimum): object
{
    $labels = array_fill(0, count($neighborhoods), -2);
    $core = array_map(fn($neighbors) => count($neighbors) >= $minimum, $neighborhoods);
    $cluster = 0;
    foreach ($labels as $p => $_) {
        if ($labels[$p] !== -2) {
            continue;
        }
        if (!$core[$p]) {
            $labels[$p] = -1;
            continue;
        }
        $labels[$p] = $cluster;
        $queue = [];
        $queued = array_fill(0, count($labels), false);
        $enqueue = function (array $neighbors) use (&$queue, &$queued, &$labels): void {
            foreach ($neighbors as $q) {
                if ($labels[$q] < 0 && !$queued[$q]) {
                    $queue[] = $q;
                    $queued[$q] = true;
                }
            }
        };
        $enqueue($neighborhoods[$p]);
        for ($head = 0; $head < count($queue); $head++) {
            $q = $queue[$head];
            $queued[$q] = false;
            if ($labels[$q] === -1) {
                $labels[$q] = $cluster;
            } elseif ($labels[$q] === -2) {
                $labels[$q] = $cluster;
                if ($core[$q]) {
                    $enqueue($neighborhoods[$q]);
                }
            }
        }
        $cluster++;
    }
    return (object) compact('labels', 'core');
}
