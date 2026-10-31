<?php
declare(strict_types=1);

function resolve_name(string $name, array $entries, bool $script): object
{
    $strong = $weak = $common = $references = $referrers = $definers = $common_shapes = [];
    foreach ($entries as $entry) {
        if ($entry->kind === 'defined') {
            if ($entry->binding === 'global') {
                $strong[] = $entry;
                $definers[] = $entry->object->name;
            } elseif ($entry->binding === 'weak') {
                $weak[] = $entry;
            }
        } elseif ($entry->kind === 'common') {
            $common[] = $entry;
            $common_shapes[$entry->size . ',' . $entry->alignment] = true;
        } else {
            $references[] = $entry;
            $referrers[$entry->object->name] = true;
        }
    }
    if ($script) {
        array_unshift($definers, '*script*');
    }
    $result = (object)['name' => $name, 'entries' => $entries, 'strong' => $strong, 'weak' => $weak,
        'common' => $common, 'references' => $references, 'referrers' => array_keys($referrers),
        'definers' => $definers, 'kind' => 'weakundef', 'definition' => null, 'definer' => '-',
        'size' => 0, 'alignment' => 1, 'live' => false, 'address' => 0, 'value' => null,
        'common_shapes' => $common_shapes, 'unresolved' => []];
    if ($script) {
        $result->kind = 'script';
        $result->definer = '*script*';
    } elseif ($strong) {
        $result->kind = 'global';
        $result->definition = $strong[0];
        $result->definer = $strong[0]->object->name;
    } elseif ($common) {
        $result->kind = 'common';
        foreach ($common as $entry) {
            $result->size = max($result->size, $entry->size);
            $result->alignment = max($result->alignment, $entry->alignment);
        }
        foreach ($common as $entry) {
            if ($entry->size === $result->size) {
                $result->definer = $entry->object->name;
                break;
            }
        }
    } elseif ($weak) {
        $result->kind = 'weak';
        $result->definition = $weak[0];
        $result->definer = $weak[0]->object->name;
    } else {
        foreach ($references as $reference) {
            if ($reference->binding === 'global') {
                $result->kind = 'undefined';
                break;
            }
        }
    }
    return $result;
}
