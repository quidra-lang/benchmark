<?php

function tryOrder(
    Grid $grid,
    array $agents,
    array $distances,
    int $horizon,
    array $order,
    Budget $budget,
): array {
    $p = new Prohibitions();
    $paths = $attempts = [];
    foreach ($order as $i) {
        try {
            [$path, $expanded] = lowSearch(
                $grid,
                $agents[$i],
                $distances[$i],
                $agents[$i]['start'],
                0,
                $p,
                $horizon,
                $budget,
            );
        } catch (BudgetExceeded) {
            return [null, $attempts, 'll_budget'];
        }
        $attempts[] = ['agent' => $i, 'path' => $path, 'expansions' => $expanded];
        if ($path === null)
            return [null, $attempts, $i];
        $paths[$i] = $path;
        $p->reserve($path, 0, true);
    }
    ksort($paths, SORT_NUMERIC);
    return [array_values($paths), $attempts, null];
}
