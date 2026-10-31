<?php

function gcd(int $a, int $b): int
{
    $a = abs($a);
    $b = abs($b);
    while ($b)
        [$a, $b] = [$b, $a % $b];
    return $a;
}

final readonly class Point
{
    public int $x, $y, $d;

    public function __construct(int $x, int $y, int $d = 1)
    {
        if ($d < 0) {
            $x = -$x;
            $y = -$y;
            $d = -$d;
        }
        $g = gcd(gcd($x, $y), $d);
        $this->x = intdiv($x, $g);
        $this->y = intdiv($y, $g);
        $this->d = intdiv($d, $g);
    }

    public function key(): string
    {
        return $this->x . ':' . $this->y . ':' . $this->d;
    }

    public function real(): array
    {
        return [(float) $this->x / (float) $this->d, (float) $this->y / (float) $this->d];
    }

    public function text(): string
    {
        return '(' . fractionText($this->x, $this->d) . ',' . fractionText($this->y, $this->d) . ')';
    }
}

final readonly class Line
{
    public function __construct(
        public int $x,
        public int $y,
        public int $dx,
        public int $dy,
    ) {}

    public static function through(Point $a, Point $b): self
    {
        return new self($a->x, $a->y, $b->x - $a->x, $b->y - $a->y);
    }

    public function side(Point $p): int
    {
        return ($this->dx * ($p->y - ($this->y * $p->d))) - ($this->dy * ($p->x - ($this->x * $p->d)));
    }
}

final readonly class Vertex
{
    public function __construct(
        public Point $point,
        public Line $line,
    ) {}
}

function fractionText(int $n, int $d = 1): string
{
    $g = gcd($n, $d);
    $n = intdiv($n, $g);
    $d = intdiv($d, $g);
    return $d === 1 ? (string) $n : $n . '/' . $d;
}

function coordinateCompare(Point $a, Point $b, bool $x): int
{
    return (($x ? $a->x : $a->y) * $b->d) <=> (($x ? $b->x : $b->y) * $a->d);
}

function pointCompare(Point $a, Point $b): int
{
    return coordinateCompare($a, $b, false) ?: coordinateCompare($a, $b, true);
}

function cross(Point $o, Point $a, Point $b): int
{
    return (($a->x - $o->x) * ($b->y - $o->y)) - (($a->y - $o->y) * ($b->x - $o->x));
}

function segmentText(Point $a, Point $b): string
{
    return $a->text() . '-' . $b->text();
}

function edgeVector(Vertex $a, Vertex $b): array
{
    $l = $a->line;
    $direction = $l->dx !== 0
        ? coordinateCompare($b->point, $a->point, true) * ($l->dx <=> 0)
        : coordinateCompare($b->point, $a->point, false) * ($l->dy <=> 0);
    return [$direction * $l->dx, $direction * $l->dy];
}
