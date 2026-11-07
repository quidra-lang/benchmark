<?php
declare(strict_types=1);

final readonly class Node
{
    public function __construct(public int $identifier, public int $x, public int $y) {}
}

final readonly class Member
{
    public function __construct(public int $identifier, public int $start, public int $end,
        public int $section, public int $material, public string $group) {}
}

final readonly class Section
{
    public function __construct(public string $name, public float $area, public float $inertia) {}
}

final readonly class Material
{
    public function __construct(public string $name, public float $young, public float $yield_stress,
        public float $density, public float $expansion) {}
}

final readonly class Support
{
    public function __construct(public int $node, public array $fixed, public array $prescribed) {}
}

final readonly class LoadCase
{
    public function __construct(public string $name, public array $lines) {}
}

final readonly class Combination
{
    public function __construct(public string $name, public array $terms) {}
}

final readonly class Model
{
    public function __construct(public array $nodes, public array $members, public array $sections,
        public array $materials, public array $supports, public array $cases,
        public array $combinations, public array $settings) {}
}

function csv_rows(string $name): array
{
    $lines = file("input/$name.csv", FILE_IGNORE_NEW_LINES);
    return array_map(static fn(string $line): array => str_getcsv($line, ',', '"', ''), array_slice($lines, 1));
}

function read_model(): Model
{
    $nodes = $sections = $materials = $members = $supports = [];
    $node_index = $section_index = $material_index = $member_index = [];
    foreach (csv_rows('nodes') as [$id, $x, $y]) {
        $node_index[(int)$id] = count($nodes);
        $nodes[] = new Node((int)$id, (int)$x, (int)$y);
    }
    foreach (csv_rows('sections') as [$name, $area, $inertia]) {
        $section_index[$name] = count($sections);
        $sections[] = new Section($name, (float)$area, (float)$inertia);
    }
    foreach (csv_rows('materials') as [$name, $young, $yield, $density, $expansion]) {
        $material_index[$name] = count($materials);
        $materials[] = new Material($name, (float)$young, (float)$yield, (float)$density, (float)$expansion);
    }
    foreach (csv_rows('members') as [$id, $start, $end, $section, $material, $group]) {
        $member_index[(int)$id] = count($members);
        $members[] = new Member((int)$id, $node_index[(int)$start], $node_index[(int)$end],
            $section_index[$section], $material_index[$material], $group);
    }
    foreach (csv_rows('supports') as [$node, $fx, $fy, $dx, $dy]) {
        $supports[] = new Support($node_index[(int)$node], [(int)$fx, (int)$fy], [(float)$dx, (float)$dy]);
    }
    $cases = $combinations = [];
    foreach (file('input/loads.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $parts = explode(' ', $line);
        $kind = array_shift($parts);
        if ($kind === 'LOADCASE') {
            $case_name = $parts[0];
            $loads = [];
        } elseif ($kind === 'END') {
            $cases[] = new LoadCase($case_name, $loads);
        } elseif ($kind === 'COMBINATION') {
            $terms = [];
            for ($i = 1; $i < count($parts); $i += 2) {
                $terms[] = [$parts[$i], (float)$parts[$i + 1]];
            }
            $combinations[] = new Combination($parts[0], $terms);
        } elseif ($kind === 'FORCE') {
            $loads[] = [$kind, $node_index[(int)$parts[0]], (float)$parts[1], (float)$parts[2]];
        } elseif ($kind === 'TEMPERATURE') {
            $loads[] = [$kind, $member_index[(int)$parts[0]], (float)$parts[1]];
        } else {
            $loads[] = [$kind];
        }
    }
    $settings = ['influence' => [], 'drawing' => []];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $parts = explode(' ', $line);
        $kind = array_shift($parts);
        switch ($kind) {
            case 'deck':
                $settings[$kind] = array_map(static fn(string $id): int => $node_index[(int)$id], $parts);
                break;
            case 'influence':
                $settings[$kind][] = $member_index[(int)$parts[0]];
                break;
            case 'vehicle':
                $axles = [];
                for ($i = 1; $i < count($parts); $i += 2) {
                    $axles[] = [(int)$parts[$i], (float)$parts[$i + 1]];
                }
                $settings[$kind] = [(int)$parts[0], $axles];
                break;
            case 'rating':
                $settings[$kind] = [$parts[0], (float)$parts[1], (float)$parts[2]];
                break;
            case 'slenderness':
                $settings[$kind] = array_map('floatval', $parts);
                break;
            case 'deflection':
                $settings[$kind] = [$parts[0], (int)$parts[1]];
                break;
            case 'vibration':
                $settings[$kind] = [$parts[0], (int)$parts[1], (int)$parts[2]];
                break;
            case 'removal':
                $settings[$kind] = $parts[0];
                break;
            case 'drawing':
                $settings[$kind][] = [$parts[0], (int)$parts[1], (int)$parts[2], (int)$parts[3]];
                break;
            default:
                $settings[$kind] = array_map('intval', $parts);
        }
    }
    return new Model($nodes, $members, $sections, $materials, $supports, $cases, $combinations, $settings);
}
