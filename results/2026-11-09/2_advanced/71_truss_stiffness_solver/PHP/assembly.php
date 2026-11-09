<?php
declare(strict_types=1);

final readonly class Geometry
{
    public function __construct(public float $length, public float $cosine, public float $sine, public array $dofs) {}
}

final readonly class MemberProperties
{
    public function __construct(public float $area, public float $inertia, public float $young,
        public float $yield_stress, public float $density, public float $expansion, public float $stiffness) {}
}

final readonly class Loading
{
    public function __construct(public array $external, public array $total, public array $temperature,
        public bool $settlement) {}
}

function member_geometry(array $nodes, array $members, array $node_dofs): array
{
    $geometry = [];
    foreach ($members as $member) {
        $start = $nodes[$member->start];
        $end = $nodes[$member->end];
        $dx = $end->x - $start->x;
        $dy = $end->y - $start->y;
        $length = sqrt($dx * $dx + $dy * $dy);
        $geometry[] = new Geometry($length, $dx / $length, $dy / $length,
            array_merge($node_dofs[$member->start], $node_dofs[$member->end]));
    }
    return $geometry;
}

function member_properties(Model $model, array $choices, array $geometry): array
{
    $result = [];
    foreach ($model->members as $i => $member) {
        $section = $model->sections[$choices[$i]];
        $material = $model->materials[$member->material];
        $result[] = new MemberProperties($section->area, $section->inertia, $material->young,
            $material->yield_stress, $material->density, $material->expansion,
            $material->young * $section->area / $geometry[$i]->length);
    }
    return $result;
}

function member_weight(MemberProperties $properties, Geometry $geometry): float
{
    return $properties->density * 9.81 * $properties->area * $geometry->length / 1000000000;
}

function member_stiffness(MemberProperties $properties, Geometry $geometry): array
{
    $k = $properties->stiffness;
    $c = $geometry->cosine;
    $s = $geometry->sine;
    $xx = $k * ($c * $c);
    $xy = $k * ($c * $s);
    $yy = $k * ($s * $s);
    return [[$xx, $xy, -$xx, -$xy], [$xy, $yy, -$xy, -$yy],
        [-$xx, -$xy, $xx, $xy], [-$xy, -$yy, $xy, $yy]];
}

function assemble(array $geometry, array $properties, int $degrees, ?int $removed = null): array
{
    $matrix = array_fill(0, $degrees, array_fill(0, $degrees, 0.0));
    foreach ($geometry as $number => $shape) {
        if ($number === $removed) {
            continue;
        }
        $local = member_stiffness($properties[$number], $shape);
        foreach ($shape->dofs as $row => $global_row) {
            foreach ($shape->dofs as $column => $global_column) {
                $matrix[$global_row][$global_column] += $local[$row][$column];
            }
        }
    }
    return $matrix;
}

function load_vectors(LoadCase $case, array $geometry, array $properties, array $node_dofs,
    int $degrees, ?int $removed = null): Loading
{
    $external = $thermal = array_fill(0, $degrees, 0.0);
    $temperature = array_fill(0, count($geometry), 0.0);
    $settlement = false;
    foreach ($case->lines as $line) {
        if ($line[0] === 'FORCE') {
            [, $node, $horizontal, $vertical] = $line;
            [$x, $y] = $node_dofs[$node];
            $external[$x] += $horizontal * 1000;
            $external[$y] += $vertical * 1000;
        } elseif ($line[0] === 'TEMPERATURE') {
            [, $number, $change] = $line;
            if ($number === $removed) {
                continue;
            }
            $member = $properties[$number];
            $shape = $geometry[$number];
            $force = $member->young * $member->area * $member->expansion * $change;
            $temperature[$number] = $force;
            $direction = [-$shape->cosine, -$shape->sine, $shape->cosine, $shape->sine];
            foreach ($shape->dofs as $i => $degree) {
                $thermal[$degree] += $force * $direction[$i];
            }
        } elseif ($line[0] === 'SELFWEIGHT') {
            foreach ($geometry as $number => $shape) {
                if ($number !== $removed) {
                    $weight = member_weight($properties[$number], $shape);
                    $external[$shape->dofs[1]] -= $weight / 2;
                    $external[$shape->dofs[3]] -= $weight / 2;
                }
            }
        } else {
            $settlement = true;
        }
    }
    $total = [];
    foreach ($external as $i => $value) {
        $total[] = $value + $thermal[$i];
    }
    return new Loading($external, $total, $temperature, $settlement);
}
