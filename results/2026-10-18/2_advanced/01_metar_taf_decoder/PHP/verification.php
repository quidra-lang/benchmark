<?php
const CATEGORIES = ['VFR', 'MVFR', 'IFR', 'LIFR'];
function covers(array $f, array $o): bool {
    $h = $o['time'] - $o['time'] % 60;
    return $f['time'] <= $o['time'] && $f['start'] <= $h && $h < $f['end'];
}

function selectTaf(array $forecasts, array $o): ?array {
    $chosen = null;
    foreach ($forecasts as $f) if (covers($f, $o) && ($chosen === null || $f['time'] >= $chosen['time'])) $chosen = $f;
    return $chosen;
}

function compareForecasts(array $observations, array $forecasts): array {
    $table = array_fill(0, 4, array_fill(0, 4, 0));
    $selected = [];
    $missing = 0;
    $temporaryHits = 0;
    foreach ($observations as $o) {
        $f = selectTaf($forecasts, $o);
        if ($f === null) {
            ++$missing;
            continue;
        }
        $states = $f['hours'][$o['time'] - $o['time'] % 60];
        $cat = $states['state']['category'];
        $possible = [$cat];
        foreach ($states['temporary'] as $c) $possible[] = $c['state']['category'];
        ++$table[array_search($cat, CATEGORIES, true)][array_search($o['state']['category'], CATEGORIES, true)];
        if (in_array($o['state']['category'], $possible, true)) ++$temporaryHits;
        $selected[] = ['observation' => $o, 'states' => $states, 'possible' => $possible];
    }
    $rows = array_map('array_sum', $table);
    $cols = [];
    $hits = 0;
    $expected = 0;
    $pod = [];
    $far = [];
    $n = array_sum($rows);
    for ($i = 0;$i < 4;++$i) {
        $cols[$i] = array_sum(array_column($table, $i));
        $hits += $table[$i][$i];
        $expected += $rows[$i] * $cols[$i];
        $pod[] = [$table[$i][$i], $cols[$i]];
        $far[] = [$rows[$i] - $table[$i][$i], $rows[$i]];
    }
    return ['table' => $table, 'rows' => $rows, 'columns' => $cols, 'total' => $n, 'hits' => $hits, 'temporaryHits' => $temporaryHits, 'noForecast' => $missing, 'selected' => $selected, 'skill' => [$n * $hits - $expected, $n * $n - $expected], 'pod' => $pod, 'far' => $far];
}
