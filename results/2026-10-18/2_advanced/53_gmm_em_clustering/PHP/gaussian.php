<?php

function determinant($component) {
    return $component['a'] * $component['c'] - $component['b'] * $component['b'];
}

function quadratic($point, $component) {
    $dx = $point['x'] - $component['mx'];
    $dy = $point['y'] - $component['my'];
    return ($component['c'] * $dx * $dx - 2 * $component['b'] * $dx * $dy + $component['a'] * $dy * $dy) / determinant($component);
}

function logWeighted($point, $component) {
    return log($component['w']) - log(2 * M_PI) - log(determinant($component)) / 2 - quadratic($point, $component) / 2;
}

function eigen($component) {
    $a = $component['a'];
    $b = $component['b'];
    $c = $component['c'];
    $h = ($a + $c) / 2;
    $half = ($a - $c) / 2;
    $g = sqrt($half * $half + $b * $b);
    $lambda1 = $h + $g;
    $lambda2 = $h - $g;
    if ($b == 0) {
        [$ux, $uy] = $a >= $c ? [1.0, 0.0] : [0.0, 1.0];
    } else {
        [$vx, $vy] = $a >= $c ? [$lambda1 - $c, $b] : [$b, $lambda1 - $a];
        $length = sqrt($vx * $vx + $vy * $vy);
        $ux = ($vx < 0 ? -$vx : $vx) / $length;
        $uy = ($vx < 0 ? -$vy : $vy) / $length;
    }
    return ['lambda1' => $lambda1, 'lambda2' => $lambda2, 'ux' => $ux, 'uy' => $uy, 'angle' => atan2($uy, $ux) * 180 / M_PI];
}

function bhattacharyya($first, $second) {
    $average = ['mx' => $first['mx'], 'my' => $first['my'], 'a' => ($first['a'] + $second['a']) / 2,
        'b' => ($first['b'] + $second['b']) / 2, 'c' => ($first['c'] + $second['c']) / 2];
    return quadratic(['x' => $second['mx'], 'y' => $second['my']], $average) / 8
        + log(determinant($average) / sqrt(determinant($first) * determinant($second))) / 2;
}
