<?php
declare(strict_types=1);

final readonly class AnalysisResult
{
    public function __construct(public string $name, public array $displacement, public array $forces,
        public array $reactions, public array $external) {}
}

function axial_forces(array $geometry, array $properties, array $displacement, array $temperature,
    ?int $removed = null): array
{
    $forces = array_fill(0, count($geometry), 0.0);
    foreach ($geometry as $number => $shape) {
        if ($number === $removed) {
            continue;
        }
        [$ix, $iy, $jx, $jy] = $shape->dofs;
        $extension = ($displacement[$jx] - $displacement[$ix]) * $shape->cosine
            + ($displacement[$jy] - $displacement[$iy]) * $shape->sine;
        $forces[$number] = $properties[$number]->stiffness * $extension - $temperature[$number];
    }
    return $forces;
}

function reactions(array $matrix, array $displacement, array $force, array $restrained): array
{
    $result = array_fill(0, count($force), 0.0);
    foreach ($restrained as $row) {
        $value = 0.0;
        foreach ($displacement as $column => $entry) {
            $value += $matrix[$row][$column] * $entry;
        }
        $result[$row] = $value - $force[$row];
    }
    return $result;
}

function superpose(Combination $combination, array $results): AnalysisResult
{
    $vectors = [];
    foreach (['displacement', 'forces', 'reactions', 'external'] as $field) {
        [$first_name, $first_factor] = $combination->terms[0];
        $target = array_map(static fn(float $value): float => $first_factor * $value,
            $results[$first_name]->$field);
        foreach (array_slice($combination->terms, 1) as [$name, $factor]) {
            foreach ($results[$name]->$field as $i => $value) {
                $target[$i] += $factor * $value;
            }
        }
        $vectors[] = $target;
    }
    return new AnalysisResult($combination->name, ...$vectors);
}

function equilibrium_residual(AnalysisResult $result, array $geometry): float
{
    $residual = [];
    foreach ($result->external as $i => $force) {
        $residual[] = $force + $result->reactions[$i];
    }
    foreach ($geometry as $number => $shape) {
        $direction = [$shape->cosine, $shape->sine, -$shape->cosine, -$shape->sine];
        foreach ($shape->dofs as $i => $degree) {
            $residual[$degree] += $result->forces[$number] * $direction[$i];
        }
    }
    return max(array_map('abs', $residual));
}
