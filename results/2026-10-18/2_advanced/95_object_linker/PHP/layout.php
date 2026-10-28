<?php
declare(strict_types=1);

require_once __DIR__ . '/object_parser.php';

function align(int $value, int $alignment): int
{
    return intdiv($value + $alignment - 1, $alignment) * $alignment;
}

final class OutputSection
{
    public bool $nobits;
    public array $sections = [], $components = [], $veneer_names = [], $veneers = [];
    public int $address = 0, $size = 0, $alignment = 1;

    public function __construct(public Segment $segment, public string $name)
    {
        $this->nobits = is_nobits($name);
    }
}

final class Segment
{
    public array $outputs;
    public int $memsz = 0, $filesz = 0, $used = 0, $paddr, $storage = 0;
    public string $image = '';

    public function __construct(public string $name, public int $base, public int $length,
        public int $fill, array $output_names)
    {
        $this->outputs = array_map(fn(string $output): OutputSection => new OutputSection($this, $output), $output_names);
        $this->paddr = $base;
    }
}

function output_for(Section $section, array $outputs): ?OutputSection
{
    foreach ($outputs as $output) {
        if (belongs($section->name, $output->name)) {
            return $output;
        }
    }
    return null;
}

function place_segment(Segment $segment): void
{
    $cursor = $segment->base;
    $segment->filesz = 0;
    foreach ($segment->outputs as $output) {
        $output->alignment = 1;
        foreach ($output->components as $component) {
            $output->alignment = max($output->alignment, $component->alignment);
        }
        $cursor = align($cursor, $output->alignment);
        $output->address = $cursor;
        foreach ($output->components as $component) {
            $cursor = align($cursor, $component->alignment);
            $component->address = $cursor;
            $cursor += $component->size;
        }
        $output->size = $cursor - $output->address;
        if (!$output->nobits) {
            $segment->filesz = $cursor - $segment->base;
        }
    }
    $segment->memsz = $cursor - $segment->base;
}
