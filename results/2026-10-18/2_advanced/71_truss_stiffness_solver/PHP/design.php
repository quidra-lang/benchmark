<?php
declare(strict_types=1);

const TRUSS_PI = 3.141592653589793;

function buckling(MemberProperties $properties, Geometry $geometry, ?float $inertia = null): float
{
    return TRUSS_PI * TRUSS_PI * $properties->young * ($inertia ?? $properties->inertia)
        / ($geometry->length * $geometry->length);
}

function utilization(float $force, MemberProperties $properties, Geometry $geometry,
    ?Section $section = null): float
{
    $area = $section?->area ?? $properties->area;
    $inertia = $section?->inertia ?? $properties->inertia;
    return max(abs($force / $area) / $properties->yield_stress,
        max(0, -$force) / buckling($properties, $geometry, $inertia));
}

function slenderness(MemberProperties $properties, Geometry $geometry, ?Section $section = null): float
{
    $area = $section?->area ?? $properties->area;
    $inertia = $section?->inertia ?? $properties->inertia;
    return $geometry->length / sqrt($inertia / $area);
}

function slenderness_limit(int $number, array $combinations, array $limits): float
{
    foreach ($combinations as $result) {
        if ($result->forces[$number] < 0) {
            return $limits[0];
        }
    }
    return $limits[1];
}

function select_section(array $members, array $sections, array $properties, array $geometry,
    array $combinations, array $limits): int
{
    foreach ($sections as $number => $section) {
        $acceptable = true;
        foreach ($members as $member) {
            if (slenderness($properties[$member], $geometry[$member], $section) > $limits[$member]) {
                $acceptable = false;
                break;
            }
            foreach ($combinations as $result) {
                if (utilization($result->forces[$member], $properties[$member], $geometry[$member], $section) > 1) {
                    $acceptable = false;
                    break;
                }
            }
            if (!$acceptable) {
                break;
            }
        }
        if ($acceptable) {
            return $number;
        }
    }
    return count($sections) - 1;
}
