<?php

function ringFromPoints(array $points): array
{
    $ring = [];
    foreach ($points as $i => $p)
        $ring[] = new Vertex($p, Line::through($p, $points[($i + 1) % count($points)]));
    return $ring;
}

function inside(array $ring, Point $p): bool
{
    $parity = false;
    foreach ($ring as $i => $v) {
        $next = $ring[($i + 1) % count($ring)];
        $a = coordinateCompare($v->point, $p, false);
        $b = coordinateCompare($next->point, $p, false);
        if ($a > 0 !== $b > 0) {
            $side = $v->line->side($p);
            if ((($side <=> 0) * ($v->line->dy <=> 0)) > 0)
                $parity = !$parity;
        }
    }
    return $parity;
}

function interior(array $sequence, Point $p): bool
{
    $parity = false;
    foreach ($sequence as $r)
        if (inside($r, $p))
            $parity = !$parity;
    return $parity;
}

function boundary(array $ring, Point $p): bool
{
    foreach ($ring as $i => $v)
        if (onSegment($p, $v->point, $ring[($i + 1) % count($ring)]->point, $v->line))
            return true;
    return false;
}

function rotateRing(array $ring): array
{
    $lowest = 0;
    foreach ($ring as $i => $v)
        if (pointCompare($v->point, $ring[$lowest]->point) < 0)
            $lowest = $i;
    return [...array_slice($ring, $lowest), ...array_slice($ring, 0, $lowest)];
}

function counterclockwise(array $ring): bool
{
    $n = count($ring);
    [$ax, $ay] = edgeVector($ring[$n - 1], $ring[0]);
    [$bx, $by] = edgeVector($ring[0], $ring[1]);
    return (($ax * $by) - ($ay * $bx)) > 0;
}

function reverseRing(array $ring): array
{
    $n = count($ring);
    $result = [];
    foreach ([0, ...range($n - 1, 1)] as $i)
        $result[] = new Vertex($ring[$i]->point, $ring[($i - 1 + $n) % $n]->line);
    return $result;
}

function normalizeRing(array $ring, bool $outer): array
{
    $ring = rotateRing($ring);
    return counterclockwise($ring) === $outer ? $ring : reverseRing($ring);
}

function assemble(array $rings): array
{
    $rotated = array_map(rotateRing(...), $rings);
    $depths = $oriented = [];
    foreach ($rotated as $i => $ring) {
        $depth = 0;
        foreach ($rotated as $j => $other)
            if ($i !== $j && inside($other, $ring[0]->point))
                ++$depth;
        $depths[$i] = $depth;
        $oriented[$i] = counterclockwise($ring) === (($depth % 2) === 0) ? $ring : reverseRing($ring);
    }
    $outer = array_values(array_filter(array_keys($rotated), fn($i) => ($depths[$i] % 2) === 0));
    usort($outer, fn($a, $b) => pointCompare($oriented[$a][0]->point, $oriented[$b][0]->point));
    $result = [];
    foreach ($outer as $i) {
        $holes = [];
        foreach ($oriented as $j => $r)
            if ($depths[$j] === ($depths[$i] + 1) && inside($oriented[$i], $r[0]->point))
                $holes[] = $r;
        usort($holes, fn($a, $b) => pointCompare($a[0]->point, $b[0]->point));
        $result[] = [$oriented[$i], ...$holes];
    }
    return $result;
}

function ringArea(array $ring): float
{
    $sum = 0.0;
    foreach ($ring as $i => $v) {
        [$x1, $y1] = $v->point->real();
        [$x2, $y2] = $ring[($i + 1) % count($ring)]->point->real();
        $sum += ($x1 * $y2) - ($x2 * $y1);
    }
    return $sum / 2.0;
}

function ringPerimeter(array $ring): float
{
    $sum = 0.0;
    foreach ($ring as $i => $v) {
        [$x1, $y1] = $v->point->real();
        [$x2, $y2] = $ring[($i + 1) % count($ring)]->point->real();
        $dx = $x2 - $x1;
        $dy = $y2 - $y1;
        $sum += sqrt(($dx * $dx) + ($dy * $dy));
    }
    return $sum;
}
