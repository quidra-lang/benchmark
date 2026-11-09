<?php
declare(strict_types=1);

require_once __DIR__ . '/object_parser.php';
require_once __DIR__ . '/archive.php';
require_once __DIR__ . '/resolver.php';
require_once __DIR__ . '/layout.php';
require_once __DIR__ . '/relocator.php';

function hex_value(int $value, int $width = 8): string
{
    return str_pad(dechex($value), $width, '0', STR_PAD_LEFT);
}

function read_script(): object
{
    $script = (object)['entry' => '', 'gc' => false, 'segments' => [], 'loads' => [], 'keeps' => [],
        'sorts' => [], 'wraps' => [], 'defines' => [], 'script_names' => [], 'checksum' => null, 'inputs' => []];
    foreach (read_lines('input/link.txt') as $line) {
        $words = explode(' ', $line);
        switch ($words[0]) {
            case 'entry': $script->entry = $words[1]; break;
            case 'gc': $script->gc = $words[1] === 'on'; break;
            case 'segment':
                $script->segments[] = new Segment($words[1], intval($words[2], 16), intval($words[3], 16),
                    intval($words[4], 16), array_slice($words, 5));
                break;
            case 'load': $script->loads[] = [$words[1], $words[2]]; break;
            case 'keep': $script->keeps[$words[1]] = true; break;
            case 'sort': $script->sorts[$words[1]] = true; break;
            case 'wrap': $script->wraps[$words[1]] = true; break;
            case 'define':
                $script->defines[] = [$words[1], substr($line, strpos($line, ' = ') + 3)];
                $script->script_names[$words[1]] = true;
                break;
            case 'checksum': $script->checksum = [$words[1], $words[2]]; break;
            default: $script->inputs[] = [$words[0], array_slice($words, 1)];
        }
    }
    $script->outputs = $script->segment_names = $script->output_names = [];
    foreach ($script->segments as $segment) {
        $script->segment_names[$segment->name] = $segment;
        foreach ($segment->outputs as $output) {
            $script->outputs[] = $output;
            $script->output_names[$output->name] = $output;
        }
    }
    return $script;
}

function load_inputs(object $script): object
{
    $state = (object)['script' => $script, 'objects' => [], 'entries' => [], 'comdats' => [],
        'extractions' => [], 'archives' => []];
    $load = static function (ObjectFile $object) use ($script, $state): void {
        $object->rank = count($state->objects);
        foreach ($object->comdats as $group) {
            if (!isset($state->comdats[$group->signature])) {
                $state->comdats[$group->signature] = (object)['keeper' => $object->name, 'discarders' => []];
            } else {
                foreach ($group->sections as $section) {
                    $section->discarded = 'comdat';
                }
                $state->comdats[$group->signature]->discarders[] = $object->name;
            }
        }
        foreach ($object->symbols as $symbol) {
            if ($symbol->binding !== 'local' && $symbol->kind === 'defined' && $symbol->section->discarded === 'comdat') {
                $symbol->kind = 'undef';
                $symbol->section = null;
                $symbol->offset = 0;
            }
            if ($symbol->kind === 'undef') {
                if (isset($script->wraps[$symbol->name])) {
                    $symbol->name = '__wrap_' . $symbol->name;
                } elseif (str_starts_with($symbol->name, '__real_') && isset($script->wraps[substr($symbol->name, 7)])) {
                    $symbol->name = substr($symbol->name, 7);
                }
            }
            if ($symbol->binding !== 'local') {
                $state->entries[$symbol->name][] = $symbol;
            }
        }
        $state->objects[] = $object;
    };
    $is_undefined = static function (string $name) use ($state, $script): bool {
        if (isset($script->script_names[$name])) {
            return false;
        }
        $referenced = $name === $script->entry;
        foreach ($state->entries[$name] ?? [] as $entry) {
            if ($entry->kind === 'defined' || $entry->kind === 'common') {
                return false;
            }
            $referenced = $referenced || ($entry->kind === 'undef' && $entry->binding === 'global');
        }
        return $referenced;
    };
    $scan = static function (string $name) use ($state, $is_undefined, $load): int {
        $state->archives[$name] ??= read_archive($name);
        return scan_archive($state->archives[$name], $is_undefined,
            static function (ObjectFile $object, string $reason) use ($state, $load): void {
                $referrer = '*entry*';
                foreach ($state->entries[$reason] ?? [] as $entry) {
                    if ($entry->kind === 'undef' && $entry->binding === 'global') {
                        $referrer = $entry->object->name;
                        break;
                    }
                }
                $state->extractions[] = [$object->name, $referrer, $reason];
                $load($object);
            });
    };
    foreach ($script->inputs as [$kind, $names]) {
        if ($kind === 'object') {
            $load(read_object($names[0]));
        } elseif ($kind === 'library') {
            $scan($names[0]);
        } else {
            do {
                $extracted = 0;
                foreach ($names as $name) {
                    $extracted += $scan($name);
                }
            } while ($extracted !== 0);
        }
    }
    $state->names = array_keys($state->entries + $script->script_names);
    sort($state->names, SORT_STRING);
    $state->globals = [];
    foreach ($state->names as $name) {
        $state->globals[$name] = resolve_name($name, $state->entries[$name] ?? [], isset($script->script_names[$name]));
    }
    return $state;
}

function assign_sections(object $state): void
{
    foreach ($state->objects as $object) {
        foreach ($object->sections as $section) {
            if ($section->discarded === 'comdat') {
                continue;
            }
            $section->output = output_for($section, $state->script->outputs);
            if ($section->output === null) {
                $section->discarded = 'orphan';
            } else {
                $section->output->sections[] = $section;
            }
        }
    }
}

function relocation_target(SymbolEntry $symbol, array $globals): ?object
{
    if ($symbol->binding === 'local') {
        return $symbol->section;
    }
    $global = $globals[$symbol->name];
    return in_array($global->kind, ['global', 'weak'], true) ? $global->definition->section
        : ($global->kind === 'common' ? $global : null);
}

function collect_garbage(object $state): void
{
    $candidates = [];
    foreach ($state->script->outputs as $output) {
        array_push($candidates, ...$output->sections);
    }
    $commons = array_values(array_filter($state->globals, static fn(object $global): bool => $global->kind === 'common'));
    if (!$state->script->gc) {
        foreach (array_merge($candidates, $commons) as $unit) {
            $unit->live = true;
        }
    } else {
        $queue = [];
        $visit = static function (?object $unit) use (&$queue): void {
            if ($unit === null || $unit->live || ($unit->kind === 'section' && ($unit->output === null || $unit->discarded !== null))) {
                return;
            }
            $unit->live = true;
            $queue[] = $unit;
        };
        foreach ($candidates as $section) {
            if (isset($state->script->keeps[$section->output->name])) {
                $visit($section);
            }
        }
        $entry = $state->globals[$state->script->entry] ?? null;
        if ($entry !== null) {
            if ($entry->kind === 'global' || $entry->kind === 'weak') {
                $visit($entry->definition->section);
            } elseif ($entry->kind === 'common') {
                $visit($entry);
            }
        }
        for ($i = 0; $i < count($queue); ++$i) {
            if ($queue[$i]->kind === 'section') {
                foreach ($queue[$i]->relocations as $relocation) {
                    $visit(relocation_target($relocation->symbol, $state->globals));
                }
            }
        }
    }
    foreach ($candidates as $section) {
        if (!$section->live) {
            $section->discarded = 'gc';
        }
    }
    $state->commons = $commons;
    $entry = $state->globals[$state->script->entry] ?? null;
    $state->entry_undefined = $entry === null || in_array($entry->kind, ['undefined', 'weakundef'], true);
    foreach ($state->objects as $object) {
        $referenced = [];
        foreach ($object->sections as $section) {
            if (!$section->live) {
                continue;
            }
            foreach ($section->relocations as $relocation) {
                if ($relocation->symbol->binding !== 'local' && $state->globals[$relocation->symbol->name]->kind === 'undefined') {
                    $referenced[$relocation->symbol->name] = true;
                }
            }
        }
        foreach (array_keys($referenced) as $name) {
            $state->globals[$name]->unresolved[] = $object->name;
        }
    }
}

function merge_strings(array $sections): object
{
    $block = (object)['kind' => 'merged', 'size' => 0, 'alignment' => 1, 'address' => 0, 'data' => '',
        'section_count' => count($sections), 'strings' => 0, 'unique' => 0, 'saved' => 0];
    $positions = [];
    $original_size = 0;
    foreach ($sections as $section) {
        $original_size += $section->size;
        $section->merged = $block;
        $section->merged_positions = [];
        $start = 0;
        for ($end = 0; $end < strlen($section->data); ++$end) {
            if ($section->data[$end] !== "\0") {
                continue;
            }
            $string = substr($section->data, $start, $end - $start + 1);
            $key = bin2hex($string);
            if (!isset($positions[$key])) {
                $positions[$key] = $block->size;
                $block->data .= $string;
                $block->size += strlen($string);
                ++$block->unique;
            }
            $section->merged_positions[$start] = $positions[$key];
            ++$block->strings;
            $start = $end + 1;
        }
    }
    $block->saved = $original_size - $block->size;
    return $block;
}

function build_components(object $state): void
{
    $commons = array_values(array_filter($state->commons, static fn(object $common): bool => $common->live));
    usort($commons, static fn(object $a, object $b): int => ($b->alignment <=> $a->alignment) ?: strcmp($a->name, $b->name));
    foreach ($state->script->outputs as $output) {
        $sections = array_values(array_filter($output->sections, static fn(Section $section): bool => $section->live));
        if (isset($state->script->sorts[$output->name])) {
            $priority = static fn(Section $section): int => $section->name === $output->name
                ? 65536 : (int)substr($section->name, strlen($output->name) + 1);
            usort($sections, static fn(Section $a, Section $b): int => $priority($a) <=> $priority($b));
        }
        $strings = array_values(array_filter($sections, static fn(Section $section): bool => $section->string));
        $merged = $strings ? merge_strings($strings) : null;
        $output->components = [];
        $inserted = false;
        foreach ($sections as $section) {
            if (!$section->string) {
                $output->components[] = $section;
            } elseif (!$inserted) {
                $output->components[] = $merged;
                $inserted = true;
            }
        }
        if ($output->name === '.bss') {
            array_push($output->components, ...$commons);
        }
        $output->veneers = [];
        $names = array_keys($output->veneer_names);
        sort($names, SORT_STRING);
        foreach ($names as $name) {
            $veneer = (object)['kind' => 'veneer', 'name' => $name, 'size' => 8, 'alignment' => 4, 'address' => 0, 'data' => ''];
            $output->components[] = $veneer;
            $output->veneers[$name] = $veneer;
        }
    }
}

function section_address(Section $section, int $offset): int
{
    return $section->string ? $section->merged->address + $section->merged_positions[$offset] : $section->address + $offset;
}

function definition_address(object $global): int
{
    return section_address($global->definition->section, $global->definition->offset);
}

function far_call(Relocation $relocation, array $globals): bool
{
    if ($relocation->type !== 'CALL24' || $relocation->symbol->binding === 'local') {
        return false;
    }
    $global = $globals[$relocation->symbol->name];
    if ($global->kind !== 'global' && $global->kind !== 'weak') {
        return false;
    }
    $value = definition_address($global) + $relocation->addend - ($relocation->section->address + $relocation->offset);
    return !in_range('CALL24', $value);
}

function place_with_veneers(object $state): void
{
    while (true) {
        build_components($state);
        foreach ($state->script->segments as $segment) {
            place_segment($segment);
        }
        $added = false;
        foreach ($state->objects as $object) {
            foreach ($object->sections as $section) {
                if (!$section->live) {
                    continue;
                }
                foreach ($section->relocations as $relocation) {
                    if (far_call($relocation, $state->globals) && !isset($section->output->veneer_names[$relocation->symbol->name])) {
                        $section->output->veneer_names[$relocation->symbol->name] = true;
                        $added = true;
                    }
                }
            }
        }
        if (!$added) {
            break;
        }
    }
    foreach ($state->script->outputs as $output) {
        foreach ($output->veneers as $veneer) {
            $veneer->data = "\x04\xf0\x1f\xe5" . little_endian(definition_address($state->globals[$veneer->name]), 4);
        }
    }
}

function load_addresses(object $script): void
{
    foreach ($script->segments as $segment) {
        $segment->paddr = $segment->base;
        $segment->storage = $segment->base + $segment->memsz;
    }
    foreach ($script->loads as [$from, $to]) {
        $source = $script->segment_names[$from];
        $destination = $script->segment_names[$to];
        $source->paddr = align($destination->storage, 4);
        $destination->storage = $source->paddr + $source->filesz;
    }
    foreach ($script->segments as $segment) {
        $segment->used = $segment->storage - $segment->base;
    }
}

function evaluate_expression(string $source, object $script, array $globals): int
{
    preg_match_all('/0x[0-9a-f]+|[0-9]+|[A-Za-z_.][A-Za-z0-9_.]*|[(),+\-]/', $source, $matches);
    $tokens = $matches[0];
    $index = 0;
    $term = static function () use (&$index, $tokens, $script, $globals, &$expression): int {
        $token = $tokens[$index++];
        if ($token === '(') {
            $value = $expression();
            ++$index;
            return $value;
        }
        if ($token[0] >= '0' && $token[0] <= '9') {
            return str_starts_with($token, '0x') ? intval($token, 16) : (int)$token;
        }
        if (($tokens[$index] ?? null) !== '(') {
            return $globals[$token]->value;
        }
        ++$index;
        if ($token === 'align') {
            $first = $expression();
            ++$index;
            $second = $expression();
            ++$index;
            return align($first, $second);
        }
        $output = $script->output_names[$tokens[$index++]];
        ++$index;
        return match ($token) {
            'start' => $output->address,
            'end' => $output->address + $output->size,
            'size' => $output->size,
            default => $output->segment->paddr + $output->address - $output->segment->base
        };
    };
    $expression = static function () use ($tokens, &$index, $term): int {
        $value = $term();
        while (in_array($tokens[$index] ?? null, ['+', '-'], true)) {
            $operator = $tokens[$index++];
            $right = $term();
            $value = $operator === '+' ? $value + $right : $value - $right;
        }
        return $value;
    };
    return $expression();
}

function symbol_value(SymbolEntry $symbol, array $globals): ?int
{
    if ($symbol->binding === 'local') {
        return section_address($symbol->section, $symbol->offset);
    }
    $global = $globals[$symbol->name];
    return match ($global->kind) {
        'global', 'weak' => definition_address($global),
        'common' => $global->address,
        'script' => $global->value,
        'weakundef' => 0,
        default => null
    };
}

function apply_relocations(object $state): void
{
    $records = $counts = [];
    foreach (RELOCATION_TYPES as $type) {
        $counts[$type] = ['total' => 0, 'ok' => 0, 'veneer' => 0, 'overflow' => 0, 'undefined' => 0];
    }
    $gp = $state->globals['_gp']->value ?? 0;
    foreach ($state->script->segments as $segment) {
        foreach ($segment->outputs as $output) {
            foreach ($output->components as $component) {
                if ($component->kind !== 'section') {
                    continue;
                }
                foreach ($component->relocations as $index => $relocation) {
                    $record = (object)['relocation' => $relocation, 'position' => $component->address + $relocation->offset,
                        'symbol' => symbol_value($relocation->symbol, $state->globals), 'value' => null, 'field' => null,
                        'width' => RELOCATION_SPECS[$relocation->type][0], 'status' => 'undefined',
                        'unpaired' => is_unpaired($component->relocations, $index)];
                    if ($record->symbol !== null) {
                        $record->status = 'ok';
                        if (far_call($relocation, $state->globals)) {
                            $record->symbol = $output->veneers[$relocation->symbol->name]->address;
                            $record->status = 'veneer';
                        }
                        $calculated = calculate($relocation->type, $record->symbol, $relocation->addend, $record->position, $gp);
                        $record->value = $calculated['value'];
                        $record->field = $calculated['field'];
                        if ($calculated['overflow']) {
                            $record->status = 'overflow';
                        }
                        $component->data = substr_replace($component->data,
                            little_endian($record->field, $record->width), $relocation->offset, $record->width);
                    }
                    $records[] = $record;
                    ++$counts[$relocation->type]['total'];
                    ++$counts[$relocation->type][$record->status];
                }
            }
        }
    }
    $state->relocations = $records;
    $state->relocation_counts = $counts;
}

function make_images(object $state): void
{
    foreach ($state->script->segments as $segment) {
        $segment->image = str_repeat(chr($segment->fill), $segment->filesz);
        foreach ($segment->outputs as $output) {
            if (!$output->nobits) {
                foreach ($output->components as $component) {
                    $segment->image = substr_replace($segment->image, $component->data,
                        $component->address - $segment->base, strlen($component->data));
                }
            }
        }
    }
    if ($state->script->checksum === null) {
        return;
    }
    [$segment_name, $symbol_name] = $state->script->checksum;
    $segment = $state->script->segment_names[$segment_name];
    $offset = definition_address($state->globals[$symbol_name]) - $segment->base;
    $segment->image = substr_replace($segment->image, "\0\0\0\0", $offset, 4);
    $total = 0;
    for ($start = 0; $start < strlen($segment->image); $start += 4) {
        $chunk = 0;
        $factor = 1;
        for ($i = 0; $i < 4; ++$i) {
            if ($start + $i < strlen($segment->image)) {
                $chunk += ord($segment->image[$start + $i]) * $factor;
            }
            $factor *= 256;
        }
        $total += $chunk;
    }
    $segment->image = substr_replace($segment->image, little_endian(modulo(-$total, 4294967296), 4), $offset, 4);
}

function diagnostics(object $state): array
{
    $lines = $orphan_counts = [];
    foreach ($state->objects as $object) {
        foreach ($object->sections as $section) {
            if ($section->discarded === 'orphan') {
                $orphan_counts[$section->name] = ($orphan_counts[$section->name] ?? 0) + 1;
            }
        }
    }
    ksort($orphan_counts, SORT_STRING);
    foreach ($orphan_counts as $name => $count) {
        $lines[] = "warning: orphan section $name discarded from $count object(s)";
    }
    foreach ($state->globals as $global) {
        if (count($global->definers) >= 2) {
            $lines[] = "error: multiple definition of {$global->name}: " . implode(' ', $global->definers);
        }
        if ($global->common && in_array($global->kind, ['global', 'script'], true)) {
            $lines[] = "warning: common symbol {$global->name} overridden by {$global->definer}";
        }
        if ($global->kind === 'common' && count($global->common_shapes) >= 2) {
            $lines[] = "warning: common symbol {$global->name} merged to size {$global->size} align {$global->alignment}";
        }
    }
    if ($state->entry_undefined) {
        $lines[] = "error: entry symbol {$state->script->entry} is undefined";
    }
    foreach ($state->globals as $global) {
        if ($global->kind === 'undefined' && $global->unresolved) {
            $lines[] = "error: undefined symbol {$global->name} referenced by " . implode(' ', $global->unresolved);
        }
    }
    foreach ($state->script->segments as $segment) {
        if ($segment->used > $segment->length) {
            $lines[] = "error: segment {$segment->name} overflows its length by " . ($segment->used - $segment->length) . ' bytes';
        }
    }
    foreach ($state->script->segments as $i => $a) {
        foreach (array_slice($state->script->segments, $i + 1) as $b) {
            if ($a->memsz > 0 && $b->memsz > 0 && $a->base < $b->base + $b->memsz && $b->base < $a->base + $a->memsz) {
                $lines[] = "error: segments {$a->name} and {$b->name} overlap";
            }
        }
    }
    foreach ($state->relocations as $record) {
        $r = $record->relocation;
        $location = "{$r->section->object->name} {$r->section->name}+{$r->offset}";
        if ($record->unpaired) {
            $lines[] = "error: unpaired HI16 at $location against {$r->symbol->name}";
        }
        if ($record->status === 'overflow') {
            $lines[] = "error: relocation overflow at $location: {$r->type} value {$record->value} against {$r->symbol->name}";
        }
    }
    $errors = $warnings = 0;
    foreach ($lines as $line) {
        $errors += (int)str_starts_with($line, 'error');
        $warnings += (int)str_starts_with($line, 'warning');
    }
    $lines[] = "errors $errors warnings $warnings";
    return $lines;
}

function entry_address(object $state): int
{
    $entry = $state->globals[$state->script->entry] ?? null;
    if ($entry === null) {
        return 0;
    }
    return in_array($entry->kind, ['global', 'weak'], true) ? definition_address($entry) : ($entry->kind === 'common' ? $entry->address : 0);
}

function image_dump(object $state, int $entry): array
{
    $lines = ['entry ' . hex_value($entry) . ' ' . $state->script->entry];
    foreach ($state->script->segments as $segment) {
        $lines[] = "segment {$segment->name} vaddr " . hex_value($segment->base) . ' paddr ' . hex_value($segment->paddr)
            . " filesz {$segment->filesz} memsz {$segment->memsz}";
        for ($start = 0; $start < strlen($segment->image); $start += 16) {
            $lines[] = hex_value($segment->base + $start) . ' ' . implode(' ', str_split(bin2hex(substr($segment->image, $start, 16)), 2));
        }
    }
    return $lines;
}

function intel_record(int $type, int $address, string $data): string
{
    $bytes = chr(strlen($data)) . chr(intdiv($address, 256)) . chr($address % 256) . chr($type) . $data;
    $sum = 0;
    for ($i = 0; $i < strlen($bytes); ++$i) {
        $sum += ord($bytes[$i]);
    }
    return ':' . strtoupper(bin2hex($bytes . chr(modulo(-$sum, 256))));
}

function intel_hex(object $state, int $entry): array
{
    $segments = array_values(array_filter($state->script->segments, static fn(Segment $segment): bool => $segment->filesz > 0));
    usort($segments, static fn(Segment $a, Segment $b): int => $a->paddr <=> $b->paddr);
    $lines = [];
    $upper = 0;
    foreach ($segments as $segment) {
        $offset = 0;
        while ($offset < $segment->filesz) {
            $address = $segment->paddr + $offset;
            $count = min(16, $segment->filesz - $offset, 65536 - $address % 65536);
            $next_upper = intdiv($address, 65536);
            if ($next_upper !== $upper) {
                $upper = $next_upper;
                $lines[] = intel_record(4, 0, chr(intdiv($upper, 256)) . chr($upper % 256));
            }
            $lines[] = intel_record(0, $address % 65536, substr($segment->image, $offset, $count));
            $offset += $count;
        }
    }
    $lines[] = intel_record(5, 0, strrev(little_endian($entry, 4)));
    $lines[] = intel_record(1, 0, '');
    return $lines;
}

function map_lines(object $state): array
{
    $lines = [];
    foreach ($state->extractions as [$object, $referrer, $reason]) {
        $lines[] = "member $object $referrer $reason";
    }
    foreach ($state->comdats as $signature => $group) {
        $lines[] = "comdat $signature {$group->keeper} " . ($group->discarders ? implode(',', $group->discarders) : '-');
    }
    foreach ($state->script->segments as $segment) {
        $lines[] = "segment {$segment->name} vaddr " . hex_value($segment->base) . ' paddr ' . hex_value($segment->paddr)
            . " filesz {$segment->filesz} memsz {$segment->memsz} used {$segment->used} length {$segment->length} "
            . intdiv(100 * $segment->used, $segment->length) . '%';
        foreach ($segment->outputs as $output) {
            $lines[] = "section {$output->name} " . hex_value($output->address) . " {$output->size} {$output->alignment}";
            foreach ($output->components as $c) {
                $address = hex_value($c->address);
                $lines[] = match ($c->kind) {
                    'section' => "input $address {$c->size} {$c->alignment} {$c->object->name} {$c->name}",
                    'merged' => "merged $address {$c->size} sections {$c->section_count} strings {$c->strings} unique {$c->unique} saved {$c->saved}",
                    'common' => "common $address {$c->size} {$c->alignment} {$c->definer} {$c->name}",
                    default => "veneer $address 8 {$c->name}"
                };
            }
        }
    }
    foreach ($state->objects as $object) {
        foreach ($object->sections as $section) {
            if ($section->discarded !== null) {
                $lines[] = "discard {$object->name} {$section->name} {$section->size} {$section->discarded}";
            }
        }
    }
    foreach ($state->commons as $common) {
        if (!$common->live) {
            $lines[] = "discard {$common->definer} COMMON({$common->name}) {$common->size} gc";
        }
    }
    $symbols = [];
    foreach ($state->globals as $global) {
        if (in_array($global->kind, ['global', 'weak'], true) && $global->definition->section->live) {
            $symbols[] = [definition_address($global), $global->name, $global->kind, $global->definer];
        } elseif ($global->kind === 'common' && $global->live) {
            $symbols[] = [$global->address, $global->name, 'common', $global->definer];
        } elseif ($global->kind === 'script') {
            $symbols[] = [$global->value, $global->name, 'script', '*script*'];
        }
    }
    foreach ($state->script->outputs as $output) {
        foreach ($output->veneers as $veneer) {
            $symbols[] = [$veneer->address, '__veneer_' . $veneer->name, 'veneer', '*linker*'];
        }
    }
    usort($symbols, static fn(array $a, array $b): int => ($a[0] <=> $b[0]) ?: strcmp($a[1], $b[1]));
    foreach ($symbols as [$address, $name, $kind, $definer]) {
        $lines[] = 'symbol ' . hex_value($address) . " $name $kind $definer";
    }
    return $lines;
}

function xref_lines(object $state): array
{
    $lines = [];
    foreach ($state->globals as $global) {
        $status = match ($global->kind) {
            'global', 'weak' => $global->definition->section->live ? 'kept' : 'discarded',
            'common' => $global->live ? 'kept' : 'discarded',
            'script' => 'kept',
            default => '-'
        };
        $lines[] = "{$global->name} {$global->kind} $status {$global->definer} " . ($global->referrers ? implode(',', $global->referrers) : '-');
    }
    return $lines;
}

function relocation_lines(object $state): array
{
    $lines = [];
    foreach ($state->relocations as $record) {
        $r = $record->relocation;
        $values = $record->status === 'undefined' ? '- - -'
            : hex_value($record->symbol) . " {$record->value} " . hex_value($record->field, 2 * $record->width);
        $lines[] = hex_value($record->position) . " {$r->section->object->name} {$r->section->name}+{$r->offset} {$r->type} {$r->symbol->name} {$r->addend} $values {$record->status}";
    }
    foreach (RELOCATION_TYPES as $type) {
        $c = $state->relocation_counts[$type];
        $lines[] = "summary $type total {$c['total']} ok {$c['ok']} veneer {$c['veneer']} overflow {$c['overflow']} undefined {$c['undefined']}";
    }
    return $lines;
}

function main(): void
{
    $script = read_script();
    $state = load_inputs($script);
    assign_sections($state);
    collect_garbage($state);
    place_with_veneers($state);
    load_addresses($script);
    foreach ($script->defines as [$name, $expression]) {
        $state->globals[$name]->value = evaluate_expression($expression, $script, $state->globals);
    }
    apply_relocations($state);
    make_images($state);
    $entry = entry_address($state);
    $outputs = ['image.hex' => image_dump($state, $entry), 'flash.ihex' => intel_hex($state, $entry),
        'link.map' => map_lines($state), 'xref.txt' => xref_lines($state),
        'relocations.txt' => relocation_lines($state), 'diagnostics.txt' => diagnostics($state)];
    if (!is_dir('output')) {
        mkdir('output');
    }
    foreach ($outputs as $name => $lines) {
        file_put_contents('output/' . $name, implode("\n", $lines) . ($lines ? "\n" : ''));
    }
}

main();
