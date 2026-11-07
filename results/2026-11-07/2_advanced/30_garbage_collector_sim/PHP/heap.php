<?php

function createObject(int $number, int $pointers, int $data): object
{
    return (object) ['number' => $number, 'pointers' => $pointers, 'data' => $data, 'size' => 1 + $pointers + $data,
        'fields' => array_fill(0, $pointers, null), 'address' => null, 'moves' => 0, 'age' => 0, 'references' => 0];
}

function addObject(array &$pair, object $object): void
{
    $pair[0]++;
    $pair[1] += $object->size;
}

function objectPair(iterable $objects): array
{
    $pair = [0, 0];
    foreach ($objects as $object) {
        addObject($pair, $object);
    }
    return $pair;
}

function freeBlocks(array $objects, int $start, int $end): array
{
    $occupied = array_values(array_filter($objects, fn($object) => $object->address >= $start && $object->address < $end));
    usort($occupied, fn($a, $b) => $a->address <=> $b->address);
    $blocks = [];
    $address = $start;
    foreach ($occupied as $object) {
        if ($object->address > $address) {
            $blocks[] = (object) ['address' => $address, 'length' => $object->address - $address];
        }
        $address = $object->address + $object->size;
    }
    if ($address < $end) {
        $blocks[] = (object) ['address' => $address, 'length' => $end - $address];
    }
    return $blocks;
}

function firstFit(array $blocks, int $size): ?int
{
    foreach ($blocks as $block) {
        if ($block->length >= $size) {
            return $block->address;
        }
    }
    return null;
}

function freeAmount(array $blocks): array
{
    $total = $largest = 0;
    foreach ($blocks as $block) {
        $total += $block->length;
        $largest = max($largest, $block->length);
    }
    return [$total, $largest];
}

function collectionRecord(int $line, int $request, string $kind, array $blocks): object
{
    return (object) ['number' => 0, 'line' => $line, 'request' => $request, 'kind' => $kind,
        'live' => [0, 0], 'freed' => [0, 0], 'moved' => [0, 0], 'promoted' => [0, 0], 'stack' => 0, 'work' => 0,
        'before' => freeAmount($blocks), 'after' => [0, 0]];
}

function dec2(int $numerator, int $denominator): string
{
    $rounded = intdiv(200 * $numerator + $denominator, 2 * $denominator);
    return intdiv($rounded, 100) . '.' . str_pad((string) ($rounded % 100), 2, '0', STR_PAD_LEFT);
}

function pct(int $numerator, int $denominator): string
{
    return $denominator === 0 ? '-' : dec2(100 * $numerator, $denominator);
}

function classTable(array $values): string
{
    $counts = [0, 0, 0, 0, 0];
    foreach ($values as $value) {
        $index = $value === 1 ? 0 : ($value <= 3 ? 1 : ($value <= 7 ? 2 : ($value <= 15 ? 3 : 4)));
        $counts[$index]++;
    }
    $labels = ['1', '2-3', '4-7', '8-15', '16+'];
    $entries = [];
    foreach ($labels as $index => $label) {
        $entries[] = $label . ':' . $counts[$index];
    }
    return implode(' ', $entries);
}

function heapMap(object $heap, object $collector, array $reachable, int $width): array
{
    $words = array_fill(0, $heap->size, '.');
    if (isset($collector->half)) {
        $inactive = $collector->half - $collector->base;
        for ($i = $inactive; $i < $inactive + $collector->half; $i++) {
            $words[$i] = '-';
        }
    }
    foreach ($heap->objects as $object) {
        $live = isset($reachable[$object->number]);
        $letter = ($object->number - 1) % 26;
        $words[$object->address] = $live ? chr(65 + $letter) : '#';
        for ($i = $object->address + 1; $i < $object->address + $object->size; $i++) {
            $words[$i] = $live ? chr(97 + $letter) : '=';
        }
    }
    $lines = [];
    for ($address = 0; $address < $heap->size; $address += $width) {
        $lines[] = str_pad((string) $address, 4, '0', STR_PAD_LEFT) . ' ' . implode('', array_slice($words, $address, $width));
    }
    return $lines;
}
