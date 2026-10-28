<?php

foreach (['rational', 'intersections', 'rings', 'greiner_hormann', 'render'] as $module)
    require_once __DIR__ . "/$module.php";
const KINDS = [
    'UNION',
    'INTERSECTION',
    'DIFFERENCE',
    'XOR',
    'CLIP',
    'AREA',
    'MOVE',
    'ROTATE',
    'MIRROR',
    'SNAP',
    'LOCATE',
    'RENDER',
];

const BINARY = ['UNION', 'INTERSECTION', 'DIFFERENCE', 'XOR', 'CLIP'];

const DEFINITIONS = ['MOVE', 'ROTATE', 'MIRROR', 'SNAP'];

const WORD_COUNTS = [
    'UNION' => 3,
    'INTERSECTION' => 3,
    'DIFFERENCE' => 3,
    'XOR' => 3,
    'CLIP' => 3,
    'AREA' => 2,
    'MOVE' => 5,
    'ROTATE' => 6,
    'MIRROR' => 5,
    'SNAP' => 3,
    'LOCATE' => 4,
    'RENDER' => 8,
];

final class Rejected extends RuntimeException {}

final class Polygon
{
    public array $rings;

    public function __construct(
        public string $name,
        public array $inputRings,
    ) {
        $outer = normalizeRing(ringFromPoints($inputRings[0]), true);
        $holes = [];
        foreach (array_slice($inputRings, 1) as $r)
            $holes[] = normalizeRing(ringFromPoints($r), false);
        usort($holes, fn($a, $b) => pointCompare($a[0]->point, $b[0]->point));
        $this->rings = [$outer, ...$holes];
    }
}

final readonly class Region
{
    public function __construct(
        public array $polygons,
        public ?array $operands = null,
    ) {}
}

function records(string $name): array
{
    $records = [];
    foreach (file('input/' . $name, FILE_IGNORE_NEW_LINES) as $i => $line)
        if ($line !== '' && $line[0] !== '#')
            $records[] = [$i + 1, $line];
    return $records;
}

function digits(string $word): bool
{
    return (bool) preg_match('/\A[0-9]{1,9}\z/', $word);
}

function integerWord(string $word): bool
{
    return (bool) preg_match('/\A-?[0-9]{1,9}\z/', $word);
}

function validName(string $word): bool
{
    return (bool) preg_match('/\A[a-z0-9_]{1,16}\z/', $word);
}

function parseRings(array $content, int $end): array
{
    $rings = [];
    $position = 0;
    while ($position < count($content)) {
        [$number, $line] = $content[$position++];
        $f = explode(' ', $line);
        if (
            count($f) !== 2
            || !in_array($f[0], ['OUTER', 'HOLE'], true)
            || !digits($f[1])
            || (int) $f[1] < 1
            || $f[0] === 'OUTER' && $rings
            || $f[0] === 'HOLE' && !$rings
        )
            return [null, $number];
        $ring = [];
        for ($i = 0; $i < (int) $f[1]; ++$i) {
            if ($position === count($content))
                return [null, $end];
            [$number, $line] = $content[$position++];
            $xy = explode(' ', $line);
            if (count($xy) !== 2 || !array_all($xy, integerWord(...)))
                return [null, $number];
            $ring[] = new Point((int) $xy[0], (int) $xy[1]);
        }
        $rings[] = $ring;
    }
    return $rings ? [$rings, null] : [null, $end];
}

function checkRing(array $ring, int $number): ?string
{
    $n = count($ring);
    if ($n < 3)
        return "too_few_vertices ring $number";
    foreach ($ring as $p)
        if ($p->x < 0 || $p->x > 1000 || $p->y < 0 || $p->y > 1000)
            return "out_of_range ring $number " . $p->text();
    $seen = [];
    foreach ($ring as $p) {
        if (isset($seen[$p->key()]))
            return "duplicate_vertex ring $number " . $p->text();
        $seen[$p->key()] = true;
    }
    foreach ($ring as $i => $p)
        if (cross($ring[($i - 1 + $n) % $n], $p, $ring[($i + 1) % $n]) === 0)
            return "collinear ring $number " . $p->text();
    for ($i = 0; $i < $n; ++$i)
        for ($j = $i + 2; $j < $n; ++$j) {
            if ($i === 0 && $j === ($n - 1))
                continue;
            $a = $ring[$i];
            $b = $ring[($i + 1) % $n];
            $c = $ring[$j];
            $d = $ring[($j + 1) % $n];
            if (segmentsTouch($a, $b, $c, $d))
                return "self_intersection ring $number " . segmentText($a, $b) . ' ' . segmentText($c, $d);
        }
    return null;
}

function checkPolygon(array $rings): ?string
{
    foreach ($rings as $i => $r)
        if (($error = checkRing($r, $i + 1)) !== null)
            return $error;
    for ($i = 0; $i < count($rings); ++$i)
        for ($j = $i + 1; $j < count($rings); ++$j) {
            $aRing = $rings[$i];
            $bRing = $rings[$j];
            foreach ($aRing as $aIndex => $a)
                foreach ($bRing as $bIndex => $c) {
                    $b = $aRing[($aIndex + 1) % count($aRing)];
                    $d = $bRing[($bIndex + 1) % count($bRing)];
                    if (segmentsTouch($a, $b, $c, $d))
                        return (
                            'rings_touch rings '
                            . ($i + 1)
                            . ' '
                            . ($j + 1)
                            . ' '
                            . segmentText($a, $b)
                            . ' '
                            . segmentText($c, $d)
                        );
                }
        }
    $edgeRings = array_map(ringFromPoints(...), $rings);
    for ($i = 1; $i < count($rings); ++$i)
        if (!inside($edgeRings[0], $rings[$i][0]))
            return 'hole_outside ring ' . ($i + 1) . ' ' . $rings[$i][0]->text();
    for ($i = 1; $i < count($rings); ++$i)
        for ($j = $i + 1; $j < count($rings); ++$j) {
            if (inside($edgeRings[$i], $rings[$j][0]))
                $p = $rings[$j][0];
            elseif (inside($edgeRings[$j], $rings[$i][0]))
                $p = $rings[$i][0];
            else
                continue;
            return 'hole_in_hole rings ' . ($i + 1) . ' ' . ($j + 1) . ' ' . $p->text();
        }
    return null;
}

function allVertices(Polygon $polygon): array
{
    $points = [];
    foreach ($polygon->rings as $r)
        foreach ($r as $v)
            $points[] = $v->point;
    return $points;
}

function allEdges(Polygon $polygon): array
{
    $edges = [];
    foreach ($polygon->rings as $r)
        foreach ($r as $i => $v)
            $edges[] = [$v->point, $r[($i + 1) % count($r)]->point, $v->line];
    return $edges;
}

function generalPosition(Polygon $a, Polygon $b): ?string
{
    $av = allVertices($a);
    $bv = allVertices($b);
    $set = [];
    foreach ($bv as $p)
        $set[$p->key()] = true;
    foreach ($av as $p)
        if (isset($set[$p->key()]))
            return 'shared_vertex ' . $p->text();
    $ae = allEdges($a);
    $be = allEdges($b);
    foreach ($ae as [$p, $q])
        foreach ($be as [$r, $s])
            if (overlap($p, $q, $r, $s))
                return 'overlapping_edges ' . segmentText($p, $q) . ' ' . segmentText($r, $s);
    foreach ([[$a, $av, $b, $be], [$b, $bv, $a, $ae]] as [$source, $vertices, $other, $edges])
        foreach ($vertices as $p)
            foreach ($edges as [$r, $s, $line])
                if (onSegment($p, $r, $s, $line))
                    return (
                        "vertex_on_edge {$source->name} "
                        . $p->text()
                        . " {$other->name} "
                        . segmentText($r, $s)
                    );
    return null;
}

function argumentsValid(array $w): bool
{
    $kind = $w[0];
    if (count($w) !== WORD_COUNTS[$kind])
        return false;
    if (in_array($kind, BINARY, true) || $kind === 'AREA')
        return true;
    if ($kind === 'SNAP')
        return validName($w[2]);
    if ($kind === 'LOCATE')
        return array_all(array_slice($w, 2), fn($v) => integerWord($v) && (int) $v >= 0 && (int) $v <= 1000);
    if ($kind === 'MOVE')
        return (
            validName($w[4])
            && array_all(
                array_slice($w, 2, 2),
                fn($v) => integerWord($v) && (int) $v >= -1000 && (int) $v <= 1000,
            )
        );
    if ($kind === 'ROTATE')
        return (
            validName($w[5])
            && array_all(array_slice($w, 2, 3), integerWord(...))
            && (int) $w[2] >= 0
            && (int) $w[2] <= 1000
            && (int) $w[3] >= 0
            && (int) $w[3] <= 1000
            && (int) $w[4] >= 1
            && (int) $w[4] <= 3
        );
    if ($kind === 'MIRROR')
        return (
            validName($w[4])
            && in_array($w[2], ['x', 'y'], true)
            && integerWord($w[3])
            && (int) $w[3] >= 0
            && (int) $w[3] <= 1000
        );
    if (!array_all(array_slice($w, 2), integerWord(...)))
        return false;
    [$x, $y, $cw, $ch, $cols, $rows] = array_map(intval(...), array_slice($w, 2));
    return (
        $x >= 0
        && $y >= 0
        && $cw >= 1
        && $cw <= 100
        && $ch >= 1
        && $ch <= 100
        && $cols >= 1
        && $cols <= 100
        && $rows >= 1
        && $rows <= 60
        && ($x + ($cw * $cols)) <= 1000
        && ($y + ($ch * $rows)) <= 1000
    );
}

function transformRings(Polygon $polygon, array $w): array
{
    $rings = [];
    foreach ($polygon->inputRings as $r) {
        $ring = [];
        foreach ($r as $p) {
            $x = $p->x;
            $y = $p->y;
            if ($w[0] === 'MOVE') {
                $x += (int) $w[2];
                $y += (int) $w[3];
            } elseif ($w[0] === 'ROTATE') {
                $cx = (int) $w[2];
                $cy = (int) $w[3];
                for ($q = 0; $q < (int) $w[4]; ++$q)
                    [$x, $y] = [$cx - ($y - $cy), $cy + ($x - $cx)];
            } elseif ($w[2] === 'x')
                $x = (2 * (int) $w[3]) - $x;
            else
                $y = (2 * (int) $w[3]) - $y;
            $ring[] = new Point($x, $y);
        }
        $rings[] = $ring;
    }
    return $rings;
}

function totalArea(array $polygons): float
{
    $area = 0.0;
    foreach ($polygons as $polygon)
        foreach ($polygon as $ring)
            $area += ringArea($ring);
    return $area;
}

function binaryResult(string $kind, Polygon $a, Polygon $b): array
{
    $graph = new GHGraph($a->rings, $b->rings);
    $intersection = assemble($graph->traverse(false, false));
    $union = assemble($graph->traverse(true, true));
    if ($kind === 'UNION')
        $polygons = $union;
    elseif ($kind === 'INTERSECTION' || $kind === 'CLIP')
        $polygons = $intersection;
    else {
        $polygons = assemble($graph->traverse(true, false));
        if ($kind === 'XOR') {
            $reverse = new GHGraph($b->rings, $a->rings);
            array_push($polygons, ...assemble($reverse->traverse(true, false)));
            usort($polygons, fn($p, $q) => pointCompare($p[0][0]->point, $q[0][0]->point));
        }
    }
    $relation = $graph->crossings
        ? 'overlap'
        : (
            $graph->na === count($a->rings) && $graph->nb === 0
                ? 'within'
                : (
                    $graph->nb === count($b->rings) && $graph->na === 0
                        ? 'contains'
                        : ($graph->na === 0 && $graph->nb === 0 ? 'disjoint' : 'overlap')
                )
        );
    return [new Region($polygons, [$a, $b]), $graph, $relation, totalArea($intersection) / totalArea($union)];
}

function cyclicEqual(array $a, array $b): bool
{
    if (count($a) !== count($b))
        return false;
    $n = count($a);
    foreach ($b as $start => $p)
        if ($p->key() === $a[0]->point->key()) {
            $match = true;
            foreach ($a as $i => $v)
                if ($v->point->key() !== $b[($start + $i) % $n]->key()) {
                    $match = false;
                    break;
                }
            if ($match)
                return true;
        }
    return false;
}

function crosscheckClip(Polygon $a, Polygon $window, array $polygons): array
{
    $clipped = [];
    foreach ($a->rings as $ring) {
        foreach ($window->rings[0] as $wi => $edge) {
            $clipLine = Line::through(
                $edge->point,
                $window->rings[0][($wi + 1) % count($window->rings[0])]->point,
            );
            $entries = [];
            $n = count($ring);
            foreach ($ring as $i => $cur) {
                $prev = $ring[($i - 1 + $n) % $n];
                $before = $clipLine->side($prev->point);
                $after = $clipLine->side($cur->point);
                if ($before > 0 !== $after > 0)
                    $entries[] = [
                        lineIntersection($prev->line, $clipLine),
                        $before > 0 ? $prev->line : $clipLine,
                    ];
                if ($after > 0)
                    $entries[] = [$cur->point, $prev->line];
            }
            $ring = [];
            $n = count($entries);
            foreach ($entries as $i => [$p, $incoming])
                $ring[] = new Vertex($p, $entries[($i + 1) % $n][1]);
        }
        $points = [];
        $n = count($ring);
        foreach ($ring as $i => $v)
            if ($v->point->key() !== $ring[($i - 1 + $n) % $n]->point->key())
                $points[] = $v->point;
        if (count($points) >= 3)
            $clipped[] = $points;
    }
    $result = [];
    foreach ($polygons as $polygon)
        array_push($result, ...$polygon);
    $matches =
        count($result) === count($clipped)
        && array_all($result, fn($r) => array_any($clipped, fn($other) => cyclicEqual($r, $other)));
    return [$matches ? 'match' : 'mismatch', count($clipped), array_sum(array_map(count(...), $clipped))];
}

function resultValues(array $polygons, Polygon $a, ?Polygon $b): object
{
    $av = $bv = [];
    foreach (allVertices($a) as $p)
        $av[$p->key()] = true;
    if ($b !== null)
        foreach (allVertices($b) as $p)
            $bv[$p->key()] = true;
    $lines = $rings = [];
    $area = $perimeter = $sx = $sy = 0.0;
    $origins = [0, 0, 0];
    $vertices = 0;
    $minX = $minY = $maxX = $maxY = null;
    foreach ($polygons as $pi => $polygon)
        foreach ($polygon as $hi => $ring) {
            $ar = ringArea($ring);
            $area += $ar;
            $perimeter += ringPerimeter($ring);
            $rings[] = [$pi + 1, $hi, $ring, $ar];
            $vertices += count($ring);
            foreach ($ring as $i => $v) {
                $p = $v->point;
                $key = $p->key();
                ++$origins[isset($av[$key]) ? 0 : (isset($bv[$key]) ? 1 : 2)];
                if ($minX === null || coordinateCompare($p, $minX, true) < 0)
                    $minX = $p;
                if ($minY === null || coordinateCompare($p, $minY, false) < 0)
                    $minY = $p;
                if ($maxX === null || coordinateCompare($p, $maxX, true) > 0)
                    $maxX = $p;
                if ($maxY === null || coordinateCompare($p, $maxY, false) > 0)
                    $maxY = $p;
                [$x1, $y1] = $p->real();
                [$x2, $y2] = $ring[($i + 1) % count($ring)]->point->real();
                $c = ($x1 * $y2) - ($x2 * $y1);
                $sx += ($x1 + $x2) * $c;
                $sy += ($y1 + $y2) * $c;
            }
        }
    $pc = count($polygons);
    $rc = count($rings);
    $holes = $rc - $pc;
    $lines[] = "polygons $pc rings $rc holes $holes vertices $vertices area " . sprintf('%.3f', $area);
    foreach ($rings as [$pi, $hi, $ring, $ar]) {
        $prefix = $hi === 0 ? "outer $pi" : "hole $pi $hi";
        $lines[] =
            $prefix
            . ' '
            . count($ring)
            . ' '
            . sprintf('%.3f', $ar)
            . ' '
            . implode(' ', array_map(fn($v) => $v->point->text(), $ring));
    }
    if ($minX === null) {
        $lines[] = 'bbox none';
        $lines[] = 'centroid none';
    } else {
        $lines[] =
            'bbox ('
            . fractionText($minX->x, $minX->d)
            . ','
            . fractionText($minY->y, $minY->d)
            . ') ('
            . fractionText($maxX->x, $maxX->d)
            . ','
            . fractionText($maxY->y, $maxY->d)
            . ')';
        $lines[] = sprintf('centroid (%.3f,%.3f)', $sx / (6.0 * $area), $sy / (6.0 * $area));
    }
    $lines[] = 'perimeter ' . sprintf('%.3f', $perimeter);
    $lines[] = "origins a {$origins[0]} b {$origins[1]} crossing {$origins[2]}";
    return (object) [
        'lines' => $lines,
        'area' => $area,
        'rings' => $rc,
        'holes' => $holes,
        'vertices' => $vertices,
    ];
}

function propertyLines(Polygon $polygon, float $area): array
{
    $orientations = [];
    foreach ($polygon->inputRings as $r) {
        $sum = 0;
        foreach ($r as $i => $p) {
            $q = $r[($i + 1) % count($r)];
            $sum += ($p->x * $q->y) - ($q->x * $p->y);
        }
        $orientations[] = $sum > 0 ? 'ccw' : 'cw';
    }
    $reflex = 0;
    foreach ($polygon->rings as $r)
        foreach ($r as $i => $v) {
            $n = count($r);
            [$ax, $ay] = edgeVector($r[($i - 1 + $n) % $n], $v);
            [$bx, $by] = edgeVector($v, $r[($i + 1) % $n]);
            if ((($ax * $by) - ($ay * $bx)) < 0)
                ++$reflex;
        }
    $points = array_map(fn($v) => $v->point, $polygon->rings[0]);
    usort($points, fn($a, $b) => coordinateCompare($a, $b, true) ?: coordinateCompare($a, $b, false));
    $chains = [];
    foreach ([$points, array_reverse($points)] as $sequence) {
        $chain = [];
        foreach ($sequence as $p) {
            while (count($chain) >= 2 && cross($chain[count($chain) - 2], $chain[count($chain) - 1], $p) <= 0)
                array_pop($chain);
            $chain[] = $p;
        }
        array_pop($chain);
        $chains[] = $chain;
    }
    $hull = [...$chains[0], ...$chains[1]];
    $sum = 0;
    foreach ($hull as $i => $p) {
        $q = $hull[($i + 1) % count($hull)];
        $sum += ($p->x * $q->y) - ($q->x * $p->y);
    }
    $hullArea = (float) $sum / 2.0;
    return [
        'input ' . implode(' ', $orientations),
        "reflex $reflex",
        'hull ' . count($hull) . ' ' . sprintf('%.3f solidity %.6f', $hullArea, $area / $hullArea),
    ];
}

function locate(array $polygons, Point $p): string
{
    foreach ($polygons as $i => $polygon) {
        if (boundary($polygon[0], $p))
            return 'boundary outer ' . ($i + 1);
        foreach (array_slice($polygon, 1) as $j => $ring)
            if (boundary($ring, $p))
                return 'boundary hole ' . ($i + 1) . ' ' . ($j + 1);
    }
    foreach ($polygons as $i => $polygon)
        if (inside($polygon[0], $p) && !array_any(array_slice($polygon, 1), fn($ring) => inside($ring, $p)))
            return 'inside polygon ' . ($i + 1);
    return 'outside';
}

function operandLocation(Polygon $polygon, Point $p): string
{
    if (array_any($polygon->rings, fn($r) => boundary($r, $p)))
        return 'boundary';
    return interior($polygon->rings, $p) ? 'inside' : 'outside';
}

final class Processor
{
    private array
        $used = [],
        $polygons = [],
        $invalid = [],
        $operations,
        $regions = [],
        $results = [],
        $areas = ['operation,rings,holes,vertices,area'],
        $drawings = [],
        $rejected = [],
        $totals,
        $accepted
    ;
    private int $blocks = 0, $validBlocks = 0, $succeeded = 0, $defined = 0, $crossings = 0;

    public function __construct()
    {
        $lines = records('polygons.txt');
        $position = 0;
        while ($position < count($lines)) {
            [$start, $header] = $lines[$position++];
            $name = explode(' ', $header)[1];
            $content = [];
            while ($lines[$position][1] !== 'END')
                $content[] = $lines[$position++];
            $end = $lines[$position++][0];
            ++$this->blocks;
            if (isset($this->used[$name])) {
                $this->invalid[] = [$name, 'duplicate_name line ' . $start];
                continue;
            }
            $this->used[$name] = true;
            [$rings, $errorLine] = parseRings($content, $end);
            if ($errorLine !== null) {
                $this->invalid[] = [$name, 'format line ' . $errorLine];
                continue;
            }
            if (($error = checkPolygon($rings)) !== null) {
                $this->invalid[] = [$name, $error];
                continue;
            }
            $this->polygons[$name] = new Polygon($name, $rings);
            ++$this->validBlocks;
        }
        $this->operations = array_column(records('operations.txt'), 1);
        $this->totals = $this->accepted = array_fill_keys(KINDS, 0);
    }

    private function resolve(string $name): Polygon
    {
        if (!isset($this->used[$name]))
            throw new Rejected('unknown_polygon ' . $name);
        if (!isset($this->polygons[$name]))
            throw new Rejected('invalid_polygon ' . $name);
        return $this->polygons[$name];
    }

    private function target(string $word): Region
    {
        if (str_starts_with($word, '@')) {
            if (!digits(substr($word, 1)) || !isset($this->regions[(int) substr($word, 1)]))
                throw new Rejected('bad_target ' . $word);
            return $this->regions[(int) substr($word, 1)];
        }
        return new Region([$this->resolve($word)->rings]);
    }

    private function check(array $w): array
    {
        $kind = $w[0];
        if (!isset(WORD_COUNTS[$kind]))
            throw new Rejected('unknown_operation ' . $kind);
        if (!argumentsValid($w))
            throw new Rejected('bad_arguments');
        $checked = [];
        if (in_array($kind, BINARY, true)) {
            $checked['a'] = $this->resolve($w[1]);
            $checked['b'] = $this->resolve($w[2]);
        } elseif (in_array($kind, ['AREA', 'MOVE', 'ROTATE', 'MIRROR'], true))
            $checked['a'] = $this->resolve($w[1]);
        else
            $checked['target'] = $this->target($w[1]);
        $name = $w[count($w) - 1];
        if (in_array($kind, DEFINITIONS, true) && isset($this->used[$name]))
            throw new Rejected('duplicate_name ' . $name);
        if ($kind === 'SNAP' && count($checked['target']->polygons) !== 1)
            throw new Rejected('not_single ' . $w[1]);
        if ($kind === 'CLIP') {
            $window = $checked['b']->rings;
            if (count($window) > 1)
                throw new Rejected('not_convex ' . $w[2]);
            $r = $window[0];
            $n = count($r);
            foreach ($r as $i => $v)
                if (cross($r[($i - 1 + $n) % $n]->point, $v->point, $r[($i + 1) % $n]->point) <= 0)
                    throw new Rejected('not_convex ' . $w[2]);
        }
        if (
            in_array($kind, BINARY, true)
            && ($error = generalPosition($checked['a'], $checked['b'])) !== null
        )
            throw new Rejected($error);
        if (in_array($kind, ['MOVE', 'ROTATE', 'MIRROR'], true)) {
            $sequence = transformRings($checked['a'], $w);
            foreach ($sequence as $r)
                foreach ($r as $p)
                    if ($p->x < 0 || $p->x > 1000 || $p->y < 0 || $p->y > 1000)
                        throw new Rejected('out_of_range ' . $name);
            $checked['defined'] = new Polygon($name, $sequence);
        } elseif ($kind === 'SNAP') {
            $sequence = [];
            foreach ($checked['target']->polygons[0] as $r) {
                $ring = [];
                foreach ($r as $v) {
                    $p = $v->point;
                    $ring[] = new Point(
                        intdiv((2 * $p->x) + $p->d, 2 * $p->d),
                        intdiv((2 * $p->y) + $p->d, 2 * $p->d),
                    );
                }
                $sequence[] = $ring;
            }
            if (($error = checkPolygon($sequence)) !== null)
                throw new Rejected('invalid_result ' . $error);
            $checked['defined'] = new Polygon($name, $sequence);
        }
        return $checked;
    }

    private function region(int $number, string $line, array $w, array $checked): void
    {
        $kind = $w[0];
        $this->results[] = "op $number $line";
        if (in_array($kind, BINARY, true)) {
            $a = $checked['a'];
            $b = $checked['b'];
            [$region, $graph, $relation, $iou] = binaryResult($kind, $a, $b);
            $this->results[] = "relation $relation iou " . sprintf('%.6f', $iou);
            $n = count($graph->crossings);
            $this->results[] = "crossings $n";
            $this->crossings += $n;
            foreach ($graph->crossings as $c)
                $this->results[] = 'crossing ' . $c->point->text() . ' ' . ($c->entering ? 'in' : 'out');
        } else {
            $a = $checked['defined'] ?? $checked['a'];
            $b = null;
            $region = new Region([$a->rings]);
        }
        $this->regions[$number] = $region;
        $v = resultValues($region->polygons, $a, $b);
        array_push($this->results, ...$v->lines);
        if (!in_array($kind, BINARY, true))
            array_push($this->results, ...propertyLines($a, $v->area));
        if ($kind === 'CLIP') {
            [$decision, $count, $vertices] = crosscheckClip($a, $b, $region->polygons);
            $this->results[] = "crosscheck $decision rings $count vertices $vertices";
        }
        $this->areas[] =
            $number
            . ':'
            . implode(':', $w)
            . ",{$v->rings},{$v->holes},{$v->vertices},"
            . sprintf('%.3f', $v->area);
    }

    public function run(): void
    {
        foreach ($this->operations as $index => $line) {
            $number = $index + 1;
            $w = explode(' ', $line);
            $kind = $w[0];
            if (isset($this->totals[$kind]))
                ++$this->totals[$kind];
            try {
                $checked = $this->check($w);
            } catch (Rejected $error) {
                $this->rejected[] = [$number, $error->getMessage()];
                continue;
            }
            ++$this->succeeded;
            ++$this->accepted[$kind];
            if (in_array($kind, DEFINITIONS, true)) {
                $p = $checked['defined'];
                $this->used[$p->name] = true;
                $this->polygons[$p->name] = $p;
                ++$this->defined;
            }
            if ($kind === 'RENDER') {
                $target = $checked['target'];
                $parameters = array_map(intval(...), array_slice($w, 2));
                [$lines, $counts] = renderGrid($target->polygons, $target->operands, ...$parameters);
                $cols = $parameters[4];
                $rows = $parameters[5];
                $this->drawings[] = "render $number {$w[1]} cols $cols rows $rows result {$counts['#']} a {$counts['a']} b {$counts['b']} both {$counts['+']}";
                array_push($this->drawings, ...$lines);
            } elseif ($kind === 'LOCATE') {
                $p = new Point((int) $w[2], (int) $w[3]);
                $target = $checked['target'];
                $this->results[] = "op $number $line";
                $this->results[] = 'location ' . locate($target->polygons, $p);
                if ($target->operands !== null)
                    $this->results[] =
                        'operands a '
                        . operandLocation($target->operands[0], $p)
                        . ' b '
                        . operandLocation($target->operands[1], $p);
            } else
                $this->region($number, $line, $w, $checked);
        }
        $this->results[] =
            "summary polygons {$this->blocks} valid {$this->validBlocks} invalid "
            . count($this->invalid)
            . " defined {$this->defined}";
        $this->results[] =
            'summary operations '
            . count($this->operations)
            . " succeeded {$this->succeeded} rejected "
            . count($this->rejected);
        $this->results[] = 'summary crossings ' . $this->crossings;
        foreach (KINDS as $kind)
            $this->results[] = "kind $kind {$this->totals[$kind]} {$this->accepted[$kind]}";
        $rejections = ['rejections ' . (count($this->invalid) + count($this->rejected))];
        foreach ($this->invalid as [$name, $reason])
            $rejections[] = "polygon $name $reason";
        foreach ($this->rejected as [$number, $reason])
            $rejections[] = "op $number $reason";
        if (!is_dir('output'))
            mkdir('output');
        foreach ([
            'results.txt' => $this->results,
            'areas.csv' => $this->areas,
            'render.txt' => $this->drawings,
            'rejections.txt' => $rejections,
        ] as $name => $lines)
            file_put_contents('output/' . $name, $lines ? implode("\n", $lines) . "\n" : '');
    }
}

new Processor()->run();
