<?php

function optics(array $neighborhoods, int $minimum, array $distances): object
{
    $count = count($neighborhoods);
    $core = [];
    foreach ($neighborhoods as $p => $neighbors) {
        if (count($neighbors) < $minimum) {
            $core[] = INF;
        } else {
            $values = array_map(fn($q) => distanceAt($distances, $p, $q), $neighbors);
            sort($values, SORT_NUMERIC);
            $core[] = $values[$minimum - 1];
        }
    }
    $reach = array_fill(0, $count, INF);
    $predecessor = array_fill(0, $count, -1);
    $processed = array_fill(0, $count, false);
    $ordering = [];
    for ($start = 0; $start < $count; $start++) {
        if ($processed[$start]) {
            continue;
        }
        $seeds = [$start => true];
        while ($seeds) {
            $p = null;
            foreach ($seeds as $candidate => $_) {
                if ($p === null || $reach[$candidate] < $reach[$p] || ($reach[$candidate] === $reach[$p] && $candidate < $p)) {
                    $p = $candidate;
                }
            }
            unset($seeds[$p]);
            $processed[$p] = true;
            $ordering[] = $p;
            if ($core[$p] === INF) {
                continue;
            }
            foreach ($neighborhoods[$p] as $q) {
                if ($processed[$q]) {
                    continue;
                }
                $value = max($core[$p], distanceAt($distances, $p, $q));
                if ($value < $reach[$q]) {
                    $reach[$q] = $value;
                    $predecessor[$q] = $p;
                    $seeds[$q] = true;
                }
            }
        }
    }
    return (object) compact('core', 'reach', 'predecessor', 'ordering');
}
