<?php

require_once __DIR__ . '/trajectory.php';

function loss_interval($p, $w, $t1, $t2, $dh, $dv)
{
    [$px, $py, $pz] = $p; [$wx, $wy, $wz] = $w;
    $qa = $wx * $wx + $wy * $wy; $qb = 2 * ($px * $wx + $py * $wy); $qc = ($px * $px + $py * $py) - $dh * $dh;
    $lo = $t1; $hi = $t2;
    if ($qa < 1e-12) { if ($qc >= 0) return null; }
    else {
        $disc = $qb * $qb - 4 * $qa * $qc;
        if ($disc <= 0) return null;
        $root = sqrt($disc);
        $lo = max($lo, $t1 + (-$qb - $root) / (2 * $qa)); $hi = min($hi, $t1 + (-$qb + $root) / (2 * $qa));
    }
    if ($wz == 0) { if (abs($pz) >= $dv) return null; }
    else {
        $r1 = (-$dv - $pz) / $wz; $r2 = ($dv - $pz) / $wz;
        $lo = max($lo, $t1 + min($r1, $r2)); $hi = min($hi, $t1 + max($r1, $r2));
    }
    if ($hi - $lo <= 1e-6) return null;
    $tc = $qa >= 1e-12 ? $t1 + (-$qb / (2 * $qa)) : $t1;
    $tc = min(max($tc, $lo), $hi); $elapsed = $tc - $t1;
    $ex = $px + $wx * $elapsed; $ey = $py + $wy * $elapsed;
    return ['lo' => $lo, 'hi' => $hi, 'tc' => $tc, 'distance' => sqrt($ex * $ex + $ey * $ey), 'vertical' => abs($pz + $wz * $elapsed)];
}

function pair_conflicts($aName, $aTrajectory, $bName, $bTrajectory, $dh, $dv)
{
    $pieces = [];
    foreach ($aTrajectory['segments'] as $a) foreach ($bTrajectory['segments'] as $b) {
        $t1 = max($a['ts'], $b['ts']); $t2 = min($a['te'], $b['te']);
        if ($t1 >= $t2) continue;
        $pa = position($a, $t1); $pb = position($b, $t1); $relative = []; $velocity = [];
        for ($i = 0; $i < 3; $i++) { $relative[] = $pa[$i] - $pb[$i]; $velocity[] = $a['velocity'][$i] - $b['velocity'][$i]; }
        $loss = loss_interval($relative, $velocity, $t1, $t2, $dh, $dv);
        if ($loss !== null) { $loss['aSegment'] = $a; $loss['bSegment'] = $b; $loss['order'] = count($pieces); $pieces[] = $loss; }
    }
    usort($pieces, fn($a, $b) => ($a['lo'] <=> $b['lo']) ?: ($a['order'] <=> $b['order']));
    $conflicts = [];
    foreach ($pieces as $piece) {
        $last = count($conflicts) - 1;
        if ($last < 0 || $piece['lo'] - $conflicts[$last]['end'] > 1e-6) {
            $conflicts[] = ['pair' => [$aName, $bName], 'name' => $aName . '-' . $bName, 'start' => $piece['lo'], 'end' => $piece['hi'], 'pieces' => [$piece], 'closest' => $piece];
        } else {
            $conflicts[$last]['pieces'][] = $piece; $conflicts[$last]['end'] = $piece['hi'];
            if ($piece['distance'] < $conflicts[$last]['closest']['distance'] - 1e-9) $conflicts[$last]['closest'] = $piece;
        }
    }
    return $conflicts;
}

function all_conflicts($trajectories, $dh, $dv)
{
    $names = array_keys($trajectories); sort($names, SORT_STRING); $result = [];
    for ($i = 0; $i < count($names); $i++) for ($j = $i + 1; $j < count($names); $j++) {
        foreach (pair_conflicts($names[$i], $trajectories[$names[$i]], $names[$j], $trajectories[$names[$j]], $dh, $dv) as $conflict) $result[] = $conflict;
    }
    usort($result, fn($a, $b) => ($a['start'] <=> $b['start']) ?: (strcmp($a['pair'][0], $b['pair'][0]) ?: strcmp($a['pair'][1], $b['pair'][1])));
    return $result;
}
