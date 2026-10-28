<?php

function onSegment(Point $p, Point $a, Point $b, ?Line $line = null): bool
{
    $line ??= Line::through($a, $b);
    if ($line->side($p) !== 0)
        return false;
    foreach ([true, false] as $x) {
        $ab = coordinateCompare($a, $b, $x);
        if ($ab <= 0) {
            if (coordinateCompare($p, $a, $x) < 0 || coordinateCompare($p, $b, $x) > 0)
                return false;
        } elseif (coordinateCompare($p, $b, $x) < 0 || coordinateCompare($p, $a, $x) > 0)
            return false;
    }
    return true;
}

function touch(Point $a, Point $b, Point $c, Point $d): bool
{
    $ab = Line::through($a, $b);
    $cd = Line::through($c, $d);
    $ac = $ab->side($c);
    $ad = $ab->side($d);
    $ca = $cd->side($a);
    $cb = $cd->side($b);
    return (
        (($ac <=> 0) * ($ad <=> 0)) < 0
        && (($ca <=> 0) * ($cb <=> 0)) < 0
        || onSegment($c, $a, $b, $ab)
        || onSegment($d, $a, $b, $ab)
        || onSegment($a, $c, $d, $cd)
        || onSegment($b, $c, $d, $cd)
    );
}

function overlap(Point $a, Point $b, Point $c, Point $d): bool
{
    $l = Line::through($a, $b);
    if ($l->side($c) !== 0 || $l->side($d) !== 0)
        return false;
    $x = $a->x !== $b->x;
    $low1 = coordinateCompare($a, $b, $x) < 0 ? $a : $b;
    $high1 = $low1 === $a ? $b : $a;
    $low2 = coordinateCompare($c, $d, $x) < 0 ? $c : $d;
    $high2 = $low2 === $c ? $d : $c;
    $low = coordinateCompare($low1, $low2, $x) > 0 ? $low1 : $low2;
    $high = coordinateCompare($high1, $high2, $x) < 0 ? $high1 : $high2;
    return coordinateCompare($low, $high, $x) < 0;
}

function lineIntersection(Line $a, Line $b): Point
{
    $den = ($a->dx * $b->dy) - ($a->dy * $b->dx);
    $gx = $b->x - $a->x;
    $gy = $b->y - $a->y;
    $num = ($gx * $b->dy) - ($gy * $b->dx);
    return new Point(($a->x * $den) + ($num * $a->dx), ($a->y * $den) + ($num * $a->dy), $den);
}

function crossing(Point $a, Point $b, Point $c, Point $d): ?array
{
    $r = Line::through($a, $b);
    $s = Line::through($c, $d);
    $den = ($r->dx * $s->dy) - ($r->dy * $s->dx);
    if (!$den)
        return null;
    $gx = $c->x - $a->x;
    $gy = $c->y - $a->y;
    $t = ($gx * $s->dy) - ($gy * $s->dx);
    $u = ($gx * $r->dy) - ($gy * $r->dx);
    if ($den < 0) {
        $den = -$den;
        $t = -$t;
        $u = -$u;
    }
    if ($t <= 0 || $t >= $den || $u <= 0 || $u >= $den)
        return null;
    return [
        [$t, $den],
        [$u, $den],
        new Point(($a->x * $den) + ($t * $r->dx), ($a->y * $den) + ($t * $r->dy), $den),
    ];
}
