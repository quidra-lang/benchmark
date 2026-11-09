<?php

function keyOf($a, $b)
{
    return $a . ',' . $b;
}

function canonical($triangle)
{
    $start = array_search(min($triangle), $triangle, true);
    return [$triangle[$start], $triangle[($start + 1) % 3], $triangle[($start + 2) % 3]];
}

class Triangulation
{
    public $points;
    public $directed = [];
    public $initial;

    public function __construct($points)
    {
        $this->points = $points;
        $this->initial = orient($points[1], $points[2], $points[3]) > 0 ? [1, 2, 3] : [1, 3, 2];
        $this->add(...$this->initial);
    }

    public function add($a, $b, $c)
    {
        $this->directed[keyOf($a, $b)] = $c;
        $this->directed[keyOf($b, $c)] = $a;
        $this->directed[keyOf($c, $a)] = $b;
    }

    public function remove($a, $b, $c)
    {
        unset($this->directed[keyOf($a, $b)], $this->directed[keyOf($b, $c)], $this->directed[keyOf($c, $a)]);
    }

    public function triangles()
    {
        $result = [];
        foreach ($this->directed as $edge => $c) {
            [$a, $b] = array_map('intval', explode(',', $edge));
            if ($a < $b && $a < $c) {
                $result[] = [$a, $b, $c];
            }
        }
        usort($result, fn($a, $b) => ($a[0] <=> $b[0]) ?: (($a[1] <=> $b[1]) ?: ($a[2] <=> $b[2])));
        return $result;
    }

    public function hullEdges()
    {
        $result = [];
        foreach ($this->directed as $edge => $third) {
            [$a, $b] = array_map('intval', explode(',', $edge));
            if (!isset($this->directed[keyOf($b, $a)])) {
                $result[] = [$a, $b];
            }
        }
        usort($result, fn($a, $b) => ($a[0] <=> $b[0]) ?: ($a[1] <=> $b[1]));
        return $result;
    }

    public function insert($site)
    {
        $points = $this->points;
        $containing = null;
        foreach ($this->triangles() as [$a, $b, $c]) {
            if (orient($points[$a], $points[$b], $points[$site]) > 0 &&
                orient($points[$b], $points[$c], $points[$site]) > 0 &&
                orient($points[$c], $points[$a], $points[$site]) > 0) {
                $containing = [$a, $b, $c];
                break;
            }
        }
        $pending = [];
        $visible = 0;
        if ($containing !== null) {
            [$a, $b, $c] = $containing;
            $this->remove($a, $b, $c);
            foreach ([[$a, $b], [$b, $c], [$c, $a]] as [$u, $v]) {
                $this->add($u, $v, $site);
                $pending[keyOf($u, $v)] = true;
            }
        } else {
            foreach ($this->hullEdges() as [$u, $v]) {
                if (orient($points[$u], $points[$v], $points[$site]) >= 0) {
                    continue;
                }
                $visible++;
                $this->add($v, $u, $site);
                $pending[keyOf($v, $u)] = true;
            }
        }
        $flips = 0;
        while ($pending) {
            $edge = array_key_first($pending);
            unset($pending[$edge]);
            [$a, $b] = array_map('intval', explode(',', $edge));
            if (($this->directed[$edge] ?? null) !== $site) {
                continue;
            }
            $q = $this->directed[keyOf($b, $a)] ?? null;
            if ($q === null || incircle($points[$a], $points[$b], $points[$site], $points[$q]) <= 0) {
                continue;
            }
            $this->remove($a, $b, $site);
            $this->remove($b, $a, $q);
            $this->add($a, $q, $site);
            $this->add($q, $b, $site);
            $pending[keyOf($a, $q)] = true;
            $pending[keyOf($q, $b)] = true;
            $flips++;
        }
        return ['site' => $site, 'kind' => $containing !== null ? 'inside' : 'outside',
            'containing' => $containing, 'visible' => $visible, 'flips' => $flips,
            'triangles' => intdiv(count($this->directed), 3), 'hull' => count($this->hullEdges())];
    }

    public function walk($point, $triangles, $numbers)
    {
        $current = $triangles[0]['sites'];
        $path = [1];
        while (true) {
            [$a, $b, $c] = $current;
            $crossed = null;
            foreach ([[$a, $b], [$b, $c], [$c, $a]] as [$u, $v]) {
                if (orient($this->points[$u], $this->points[$v], $point) < 0) {
                    $crossed = [$u, $v];
                    break;
                }
            }
            if ($crossed === null) {
                return ['path' => $path, 'triangle' => end($path), 'outside' => null];
            }
            [$u, $v] = $crossed;
            $third = $this->directed[keyOf($v, $u)] ?? null;
            if ($third === null) {
                return ['path' => $path, 'triangle' => null, 'outside' => [min($u, $v), max($u, $v)]];
            }
            $current = canonical([$v, $u, $third]);
            $path[] = $numbers[implode(',', $current)];
        }
    }
}
