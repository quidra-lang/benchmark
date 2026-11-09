<?php

function orient($p, $q, $r)
{
    return ($q['x'] - $p['x']) * ($r['y'] - $p['y']) - ($q['y'] - $p['y']) * ($r['x'] - $p['x']);
}

function d2($p, $q)
{
    return ($p['x'] - $q['x']) * ($p['x'] - $q['x']) + ($p['y'] - $q['y']) * ($p['y'] - $q['y']);
}

function dot($o, $p, $q)
{
    return ($p['x'] - $o['x']) * ($q['x'] - $o['x']) + ($p['y'] - $o['y']) * ($q['y'] - $o['y']);
}

function incircle($a, $b, $c, $d)
{
    $ax = $a['x'] - $d['x'];
    $ay = $a['y'] - $d['y'];
    $bx = $b['x'] - $d['x'];
    $by = $b['y'] - $d['y'];
    $cx = $c['x'] - $d['x'];
    $cy = $c['y'] - $d['y'];
    $aa = $ax * $ax + $ay * $ay;
    $bb = $bx * $bx + $by * $by;
    $cc = $cx * $cx + $cy * $cy;
    return $ax * ($by * $cc - $bb * $cy) - $ay * ($bx * $cc - $bb * $cx) + $aa * ($bx * $cy - $by * $cx);
}

function circumcenter($a, $b, $c)
{
    $bx = $b['x'] - $a['x'];
    $by = $b['y'] - $a['y'];
    $cx = $c['x'] - $a['x'];
    $cy = $c['y'] - $a['y'];
    $bb = $bx * $bx + $by * $by;
    $cc = $cx * $cx + $cy * $cy;
    $d = 2 * ($bx * $cy - $by * $cx);
    return ['X' => $a['x'] * $d + $cy * $bb - $by * $cc,
        'Y' => $a['y'] * $d + $bx * $cc - $cx * $bb, 'D' => $d];
}

function gcdInt($a, $b)
{
    $a = abs($a);
    $b = abs($b);
    while ($b !== 0) {
        [$a, $b] = [$b, $a % $b];
    }
    return $a;
}

function fraction($numerator, $denominator)
{
    $divisor = gcdInt($numerator, $denominator);
    $top = intdiv($numerator, $divisor);
    $bottom = intdiv($denominator, $divisor);
    return $bottom === 1 ? (string)$top : $top . '/' . $bottom;
}

function direction($a, $b)
{
    $dx = $b['x'] - $a['x'];
    $dy = $b['y'] - $a['y'];
    $divisor = gcdInt($dx, $dy);
    return [intdiv($dy, $divisor), intdiv(-$dx, $divisor)];
}
