<?php
declare(strict_types=1);

require_once __DIR__ . '/schema_io.php';
require_once __DIR__ . '/bitstream.php';
require_once __DIR__ . '/encoding.php';
require_once __DIR__ . '/query.php';

const TV_TRUE = 1;
const TV_FALSE = 0;
const TV_UNKNOWN = 2;
const SCAN_FIELDS = ['row_groups_read', 'row_groups_skipped', 'pages_read', 'pages_skipped',
    'pages_unneeded', 'dictionary_pages_read', 'bytes_read', 'rows_scanned', 'rows_matched'];

enum RecoveryValue { case LOST; }

function compare_values(mixed $first, mixed $second): int
{
    if ($first === $second) {
        return 0;
    }
    if ($first === null) {
        return -1;
    }
    if ($second === null) {
        return 1;
    }
    return is_string($first) ? strcmp($first, $second) : $first <=> $second;
}

function statistics(array $values): ?object
{
    $result = null;
    foreach ($values as $value) {
        if ($value === null) {
            continue;
        }
        if ($result === null) {
            $result = (object)['minimum' => $value, 'maximum' => $value];
        } else {
            if (compare_values($value, $result->minimum) < 0) {
                $result->minimum = $value;
            }
            if (compare_values($value, $result->maximum) > 0) {
                $result->maximum = $value;
            }
        }
    }
    return $result;
}

function page_bytes(object $column, int $kind, int $method, int $count, int $nulls,
    ?object $stats, string $body): string
{
    return chr($kind) . chr($method) . uleb($count) . uleb($nulls) . uleb(strlen($body))
        . uint32(adler32($body)) . statistics_bytes($column->type, $stats) . $body;
}

function data_page(object $column, int $method, array $values, array $dictionary, array $ranks): string
{
    $body = '';
    if ($column->nullable) {
        $definitions = hybrid_encode(array_map(static fn(mixed $v): int => $v === null ? 0 : 1, $values), 1);
        $body = uint32(strlen($definitions)) . $definitions;
    }
    $present = array_values(array_filter($values, static fn(mixed $v): bool => $v !== null));
    $body .= encode_values($column->type, $method, $present, $dictionary, $ranks);
    return page_bytes($column, 0, $method, count($values), count($values) - count($present), statistics($values), $body);
}

function build_chunk(object $column, array $values, int $method, array $options): object
{
    $pages = array_chunk($values, $options['page_size']);
    $dictionary = [];
    $dictionary_pages = 0;
    if ($method === 1) {
        $known = [];
        $size = 0;
        foreach ($pages as $page) {
            $additions = [];
            $proposed = $size;
            foreach ($page as $value) {
                if ($value === null || isset($known[$value]) || isset($additions[$value])) {
                    continue;
                }
                $additions[$value] = $value;
                $proposed += strlen(encode_values($column->type, 0, [$value]));
            }
            if ($proposed > $options['dictionary_limit']) {
                break;
            }
            foreach ($additions as $value) {
                $dictionary[] = $value;
                $known[$value] = true;
            }
            $size = $proposed;
            ++$dictionary_pages;
        }
        if (!$dictionary) {
            $dictionary_pages = 0;
        }
    }
    $ranks = array_flip($dictionary);
    $bytes = '';
    if ($dictionary_pages > 0) {
        $body = encode_values($column->type, 0, $dictionary);
        $bytes .= page_bytes($column, 1, 0, count($dictionary), 0, null, $body);
    }
    $methods = [];
    foreach ($pages as $index => $page) {
        $page_method = $method === 1 ? ($index < $dictionary_pages ? 1 : 0) : $method;
        $methods[$page_method] = true;
        $bytes .= data_page($column, $page_method, $page, $dictionary, $ranks);
    }
    $method_list = array_keys($methods);
    sort($method_list, SORT_NUMERIC);
    return (object)['bytes' => $bytes, 'methods' => $method_list, 'has_dictionary' => $dictionary_pages > 0,
        'page_count' => count($pages), 'nulls' => count($values) - count(array_filter($values, static fn(mixed $v): bool => $v !== null)),
        'statistics' => statistics($values), 'fallback' => $method === 1 ? count($pages) - $dictionary_pages : 0];
}

function footer_bytes(array $schema, int $row_count, array $groups): string
{
    $bytes = uleb(1) . uleb(count($schema));
    foreach ($schema as $column) {
        $bytes .= uleb(strlen($column->name)) . $column->name . chr(array_search($column->type, TYPES, true)) . chr($column->nullable ? 1 : 0);
    }
    $bytes .= uleb($row_count) . uleb(count($groups));
    foreach ($groups as $group) {
        $bytes .= uleb($group->count);
        foreach ($group->chunks as $chunk) {
            $bytes .= uleb($chunk->offset) . uleb(strlen($chunk->bytes)) . uleb(count($chunk->methods))
                . implode('', array_map('chr', $chunk->methods)) . chr($chunk->has_dictionary ? 1 : 0)
                . uleb($chunk->page_count) . uleb($chunk->nulls) . statistics_bytes($chunk->column->type, $chunk->statistics);
        }
    }
    return $bytes;
}

function write_table(object $input): array
{
    $bytes = 'MPTC';
    $groups = [];
    $report = ['row_group,column,encoding,bytes,fallback_pages,chosen'];
    foreach (array_chunk($input->table, $input->options['row_group_size']) as $rows) {
        $group = (object)['count' => count($rows), 'chunks' => []];
        foreach ($input->schema as $column) {
            $values = array_column($rows, $column->number);
            $candidates = [];
            foreach (CANDIDATES[$column->type] as $method) {
                $candidates[$method] = build_chunk($column, $values, $method, $input->options);
            }
            $chosen = array_key_first($candidates);
            if ($input->options['encodings'][$column->name] === 'AUTO') {
                foreach ($candidates as $method => $candidate) {
                    if (strlen($candidate->bytes) < strlen($candidates[$chosen]->bytes)) {
                        $chosen = $method;
                    }
                }
            } else {
                $chosen = array_search($input->options['encodings'][$column->name], METHODS, true);
                if ($chosen === 1 && !$candidates[$chosen]->has_dictionary) {
                    $chosen = 0;
                }
            }
            foreach ($candidates as $method => $candidate) {
                $report[] = count($groups) . ',' . $column->name . ',' . METHODS[$method] . ',' . strlen($candidate->bytes)
                    . ',' . $candidate->fallback . ',' . ($method === $chosen ? 'yes' : 'no');
            }
            $chunk = clone $candidates[$chosen];
            $chunk->offset = strlen($bytes);
            $chunk->column = $column;
            $group->chunks[] = $chunk;
            $bytes .= $chunk->bytes;
        }
        $groups[] = $group;
    }
    $footer = footer_bytes($input->schema, count($input->table), $groups);
    return [$bytes . $footer . uint32(strlen($footer)) . 'MPTC', $report];
}

function parse_pages(string $bytes, object $column, object $chunk, int $first_row): void
{
    $reader = new Reader($bytes, $chunk->offset);
    $chunk->pages = $chunk->data_pages = [];
    $chunk->dictionary = null;
    $row = $first_row;
    while ($reader->position < $chunk->offset + $chunk->size) {
        $offset = $reader->position;
        $kind = $reader->byte();
        $method = $reader->byte();
        $count = $reader->uleb();
        $nulls = $reader->uleb();
        $body_size = $reader->uleb();
        $checksum = $reader->uint32();
        $stats = read_statistics($reader, $column->type);
        $body_offset = $reader->position;
        $page = (object)['offset' => $offset, 'kind' => $kind, 'method' => $method, 'count' => $count,
            'nulls' => $nulls, 'body_size' => $body_size, 'checksum' => $checksum, 'statistics' => $stats,
            'header_size' => $body_offset - $offset, 'body_offset' => $body_offset];
        $chunk->pages[] = $page;
        if ($kind === 1) {
            $chunk->dictionary = $page;
        } else {
            $page->number = count($chunk->data_pages);
            $page->first_row = $row;
            $row += $count;
            $chunk->data_pages[] = $page;
        }
        $reader->position += $body_size;
    }
}

function parse_file(string $bytes): object
{
    $footer_size = (new Reader($bytes, strlen($bytes) - 8))->uint32();
    $footer_offset = strlen($bytes) - 8 - $footer_size;
    $reader = new Reader($bytes, $footer_offset);
    $version = $reader->uleb();
    $columns = $reader->uleb();
    $schema = [];
    for ($number = 0; $number < $columns; ++$number) {
        $name = $reader->text($reader->uleb());
        $schema[] = (object)['name' => $name, 'type' => TYPES[$reader->byte()], 'nullable' => $reader->byte() === 1, 'number' => $number];
    }
    $row_count = $reader->uleb();
    $group_count = $reader->uleb();
    $groups = [];
    $first_row = 0;
    for ($number = 0; $number < $group_count; ++$number) {
        $count = $reader->uleb();
        $group = (object)['number' => $number, 'count' => $count, 'first_row' => $first_row, 'chunks' => []];
        foreach ($schema as $column) {
            $offset = $reader->uleb();
            $size = $reader->uleb();
            $method_bytes = $reader->take($reader->uleb());
            $methods = array_map('ord', str_split($method_bytes));
            $has_dictionary = $reader->byte() === 1;
            $page_count = $reader->uleb();
            $nulls = $reader->uleb();
            $stats = read_statistics($reader, $column->type);
            $chunk = (object)['column' => $column, 'offset' => $offset, 'size' => $size, 'methods' => $methods,
                'has_dictionary' => $has_dictionary, 'page_count' => $page_count, 'nulls' => $nulls, 'statistics' => $stats];
            parse_pages($bytes, $column, $chunk, $first_row);
            $group->chunks[] = $chunk;
        }
        $groups[] = $group;
        $first_row += $count;
    }
    return (object)compact('bytes', 'footer_offset', 'footer_size', 'version', 'schema', 'row_count', 'groups');
}

function body_of(object $file, object $page): string
{
    return substr($file->bytes, $page->body_offset, $page->body_size);
}

function decode_dictionary(object $file, object $chunk): array
{
    return decode_values($chunk->column->type, 0, new Reader(body_of($file, $chunk->dictionary)), $chunk->dictionary->count);
}

function decode_page(object $file, object $chunk, object $page, array $dictionary = []): array
{
    $reader = new Reader(body_of($file, $page));
    $definitions = array_fill(0, $page->count, 1);
    if ($chunk->column->nullable) {
        $levels = new Reader($reader->take($reader->uint32()));
        $definitions = hybrid_decode($levels, $page->count, 1);
    }
    $count = 0;
    foreach ($definitions as $value) {
        $count += (int)($value === 1);
    }
    $values = decode_values($chunk->column->type, $page->method, $reader, $count, $dictionary);
    $next = 0;
    $result = [];
    foreach ($definitions as $value) {
        $result[] = $value === 1 ? $values[$next++] : null;
    }
    return $result;
}

function checksum_text(int $value): string
{
    return sprintf('%08x', $value);
}

function statistics_text(object $column, ?object $stats): string
{
    return $stats === null ? 'stats none'
        : 'min ' . value_text($stats->minimum, $column->type) . ' max ' . value_text($stats->maximum, $column->type);
}

function column_lines(array $schema): array
{
    return array_map(static fn(object $c): string => "column {$c->number} {$c->name} {$c->type} "
        . ($c->nullable ? 'NULLABLE' : 'REQUIRED'), $schema);
}

function method_list(array $methods): string
{
    return implode(',', array_map(static fn(int $method): string => METHODS[$method], $methods));
}

function metadata(object $file, array $table): array
{
    $lines = ['file bytes ' . strlen($file->bytes) . " footer_offset {$file->footer_offset} footer_bytes {$file->footer_size}",
        "table version {$file->version} rows {$file->row_count} columns " . count($file->schema) . ' row_groups ' . count($file->groups),
        ...column_lines($file->schema)];
    $summaries = array_map(static fn(): object => (object)['bytes' => 0, 'pages' => 0, 'dictionaries' => 0, 'methods' => []], $file->schema);
    $cells = $nulls = $mismatches = $checksum_errors = 0;
    foreach ($file->groups as $group) {
        $group_bytes = 0;
        foreach ($group->chunks as $chunk) {
            $group_bytes += $chunk->size;
        }
        $lines[] = "row_group {$group->number} rows {$group->count} first_row {$group->first_row} bytes $group_bytes";
        foreach ($group->chunks as $chunk) {
            $column = $chunk->column;
            $lines[] = "chunk {$group->number} {$column->name} offset {$chunk->offset} size {$chunk->size} encodings "
                . method_list($chunk->methods) . ' dictionary ' . ($chunk->has_dictionary ? 'yes' : 'no')
                . " pages {$chunk->page_count} nulls {$chunk->nulls} " . statistics_text($column, $chunk->statistics);
            foreach ($chunk->pages as $page) {
                $checksum_errors += (int)(adler32(body_of($file, $page)) !== $page->checksum);
                $label = $page->kind === 1 ? 'dict' : $page->number;
                $line = "page {$group->number} {$column->name} $label offset {$page->offset} header {$page->header_size} body {$page->body_size} checksum "
                    . checksum_text($page->checksum);
                $lines[] = $line . ($page->kind === 1 ? " entries {$page->count}" : ' encoding ' . METHODS[$page->method]
                    . " values {$page->count} nulls {$page->nulls} " . statistics_text($column, $page->statistics));
            }
            $dictionary = $chunk->dictionary === null ? [] : decode_dictionary($file, $chunk);
            foreach ($chunk->data_pages as $page) {
                foreach (decode_page($file, $chunk, $page, $dictionary) as $index => $value) {
                    ++$cells;
                    $nulls += (int)($value === null);
                    $mismatches += (int)($value !== $table[$page->first_row + $index][$column->number]);
                }
            }
            $summary = $summaries[$column->number];
            $summary->bytes += $chunk->size;
            $summary->pages += $chunk->page_count;
            $summary->dictionaries += (int)$chunk->has_dictionary;
            foreach ($chunk->methods as $method) {
                $summary->methods[$method] = true;
            }
        }
    }
    foreach ($file->schema as $column) {
        $summary = $summaries[$column->number];
        $methods = array_keys($summary->methods);
        sort($methods, SORT_NUMERIC);
        $lines[] = "summary {$column->name} bytes {$summary->bytes} data_pages {$summary->pages} dictionary_pages {$summary->dictionaries} encodings " . method_list($methods);
    }
    $status = $mismatches === 0 && $checksum_errors === 0 ? 'ok' : 'failed';
    $lines[] = "roundtrip $status cells $cells nulls $nulls mismatches $mismatches checksum_errors $checksum_errors";
    return $lines;
}

function comparison_nodes(?object $condition): array
{
    if ($condition === null) {
        return [];
    }
    if ($condition->kind === 'comparison') {
        return [$condition];
    }
    return $condition->kind === 'NOT' ? comparison_nodes($condition->child)
        : array_merge(comparison_nodes($condition->left), comparison_nodes($condition->right));
}

function check_query(object $query, array $schema): ?string
{
    if ($query->star) {
        $query->items = array_map(static fn(object $c): object => (object)['kind' => 'column', 'name' => $c->name], $schema);
    }
    $by_name = [];
    foreach ($schema as $column) {
        $by_name[$column->name] = $column;
    }
    $comparisons = comparison_nodes($query->condition);
    $names = [];
    foreach ($query->items as $item) {
        if ($item->name !== null) {
            $names[] = $item->name;
        }
    }
    foreach ($comparisons as $comparison) {
        $names[] = $comparison->name;
    }
    if ($query->group !== null) {
        $names[] = $query->group;
    }
    if ($query->order !== null) {
        $names[] = $query->order->name;
    }
    foreach ($names as $name) {
        if (!isset($by_name[$name])) {
            return 'unknown_column';
        }
    }
    foreach ($comparisons as $comparison) {
        $expected = match ($by_name[$comparison->name]->type) { 'INT' => 'integer', 'BOOL' => 'boolean', default => 'string' };
        foreach ($comparison->literals as $literal) {
            if ($literal->type !== $expected) {
                return 'type_mismatch';
            }
        }
    }
    $query->aggregate = $query->group !== null;
    foreach ($query->items as $item) {
        if ($item->kind === 'aggregate') {
            $query->aggregate = true;
            if (in_array($item->function, ['SUM', 'AVG'], true) && $by_name[$item->name]->type !== 'INT') {
                return 'bad_aggregate';
            }
        }
    }
    if ($query->aggregate) {
        foreach ($query->items as $item) {
            if ($item->kind === 'column' && $item->name !== $query->group) {
                return 'not_grouped';
            }
        }
        if ($query->order !== null) {
            return 'bad_order';
        }
    }
    foreach ($comparisons as $comparison) {
        $column = $by_name[$comparison->name];
        $comparison->column = $column->number;
        $comparison->values = array_map(static fn(object $literal): mixed => $column->type === 'DATE'
            ? day_number($literal->value) : $literal->value, $comparison->literals);
    }
    foreach ($query->items as $item) {
        if ($item->name !== null) {
            $item->column = $by_name[$item->name]->number;
        }
    }
    $query->group_column = $query->group === null ? null : $by_name[$query->group]->number;
    if ($query->order !== null) {
        $query->order->column = $by_name[$query->order->name]->number;
    }
    $query->needed = array_values(array_unique(array_map(static fn(string $name): int => $by_name[$name]->number, $names)));
    $query->condition_columns = array_values(array_unique(array_map(static fn(object $c): int => $c->column, $comparisons)));
    sort($query->needed, SORT_NUMERIC);
    sort($query->condition_columns, SORT_NUMERIC);
    $query->remaining = array_values(array_diff($query->needed, $query->condition_columns));
    $query->headers = array_map(static fn(object $item): string => $item->kind === 'column' ? $item->name
        : $item->function . '(' . ($item->distinct ? 'DISTINCT ' : '') . ($item->name ?? '*') . ')', $query->items);
    return null;
}

function logical(string $operator, int $first, ?int $second = null): int
{
    if ($operator === 'NOT') {
        return $first === TV_UNKNOWN ? TV_UNKNOWN : 1 - $first;
    }
    if ($operator === 'AND') {
        return $first === TV_FALSE || $second === TV_FALSE ? TV_FALSE
            : ($first === TV_UNKNOWN || $second === TV_UNKNOWN ? TV_UNKNOWN : TV_TRUE);
    }
    return $first === TV_TRUE || $second === TV_TRUE ? TV_TRUE
        : ($first === TV_UNKNOWN || $second === TV_UNKNOWN ? TV_UNKNOWN : TV_FALSE);
}

function comparison_truth(object $condition, mixed $value): int
{
    $operator = $condition->operator;
    $values = $condition->values;
    if ($operator === 'IS NULL') {
        return $value === null ? TV_TRUE : TV_FALSE;
    }
    if ($operator === 'IS NOT NULL') {
        return $value === null ? TV_FALSE : TV_TRUE;
    }
    if ($value === null) {
        return TV_UNKNOWN;
    }
    $order = compare_values($value, $values[0]);
    $result = match ($operator) {
        '=' => $order === 0, '<>' => $order !== 0, '<' => $order < 0, '<=' => $order <= 0,
        '>' => $order > 0, '>=' => $order >= 0,
        'BETWEEN' => $order >= 0 && compare_values($value, $values[1]) <= 0,
        'IN' => in_array($value, $values, true)
    };
    return $result ? TV_TRUE : TV_FALSE;
}

function evaluate(?object $condition, array $values): int
{
    if ($condition === null) {
        return TV_TRUE;
    }
    if ($condition->kind === 'comparison') {
        return comparison_truth($condition, $values[$condition->column]);
    }
    return $condition->kind === 'NOT' ? logical('NOT', evaluate($condition->child, $values))
        : logical($condition->kind, evaluate($condition->left, $values), evaluate($condition->right, $values));
}

function zone_comparison(object $condition, object $information): array
{
    $result = [];
    $operator = $condition->operator;
    $values = $condition->values;
    $count = $information->count;
    $nulls = $information->nulls;
    $stats = $information->statistics;
    if ($operator === 'IS NULL' || $operator === 'IS NOT NULL') {
        if ($nulls > 0) {
            $result[$operator === 'IS NULL' ? TV_TRUE : TV_FALSE] = true;
        }
        if ($nulls < $count) {
            $result[$operator === 'IS NULL' ? TV_FALSE : TV_TRUE] = true;
        }
        return $result;
    }
    if ($nulls > 0) {
        $result[TV_UNKNOWN] = true;
    }
    if ($stats === null) {
        return $result;
    }
    $lo = $stats->minimum;
    $hi = $stats->maximum;
    $x = $values[0];
    $low = compare_values($lo, $x);
    $high = compare_values($hi, $x);
    [$can_true, $can_false] = match ($operator) {
        '=' => [$low <= 0 && $high >= 0, !($low === 0 && $high === 0)],
        '<>' => [!($low === 0 && $high === 0), $low <= 0 && $high >= 0],
        '<' => [$low < 0, $high >= 0], '<=' => [$low <= 0, $high > 0],
        '>' => [$high > 0, $low <= 0], '>=' => [$high >= 0, $low < 0],
        'BETWEEN' => [compare_values($lo, $values[1]) <= 0 && $high >= 0 && compare_values($x, $values[1]) <= 0,
            $low < 0 || compare_values($hi, $values[1]) > 0],
        default => [false, false]
    };
    if ($operator === 'IN') {
        foreach ($values as $value) {
            $can_true = $can_true || (compare_values($lo, $value) <= 0 && compare_values($hi, $value) >= 0);
        }
        $can_false = !(compare_values($lo, $hi) === 0 && in_array($lo, $values, true));
    }
    if ($can_true) {
        $result[TV_TRUE] = true;
    }
    if ($can_false) {
        $result[TV_FALSE] = true;
    }
    return $result;
}

function zone_values(object $condition, callable $information): array
{
    if ($condition->kind === 'comparison') {
        return zone_comparison($condition, $information($condition->column));
    }
    $result = [];
    if ($condition->kind === 'NOT') {
        foreach (array_keys(zone_values($condition->child, $information)) as $value) {
            $result[logical('NOT', $value)] = true;
        }
    } else {
        foreach (array_keys(zone_values($condition->left, $information)) as $a) {
            foreach (array_keys(zone_values($condition->right, $information)) as $b) {
                $result[logical($condition->kind, $a, $b)] = true;
            }
        }
    }
    return $result;
}

function scan_file(object $file, object $query): array
{
    $counts = array_fill_keys(SCAN_FIELDS, 0);
    $records = $rows = [];
    $dictionaries = new SplObjectStorage();
    $decode = static function (object $chunk, object $page) use ($file, $dictionaries, &$counts): array {
        $dictionary = [];
        if ($page->method === 1) {
            if (!$dictionaries->contains($chunk)) {
                $dictionaries[$chunk] = decode_dictionary($file, $chunk);
                ++$counts['dictionary_pages_read'];
                $counts['bytes_read'] += $chunk->dictionary->header_size + $chunk->dictionary->body_size;
            }
            $dictionary = $dictionaries[$chunk];
        }
        ++$counts['pages_read'];
        $counts['bytes_read'] += $page->header_size + $page->body_size;
        return decode_page($file, $chunk, $page, $dictionary);
    };
    foreach ($file->groups as $group) {
        $information = static function (int $column) use ($group): object {
            $info = clone $group->chunks[$column];
            $info->count = $group->count;
            return $info;
        };
        if ($query->condition !== null && !isset(zone_values($query->condition, $information)[TV_TRUE])) {
            ++$counts['row_groups_skipped'];
            $records[] = (object)['number' => $group->number, 'skipped' => true];
            continue;
        }
        ++$counts['row_groups_read'];
        if (!$query->needed) {
            $counts['rows_scanned'] += $group->count;
            for ($i = 0; $i < $group->count; ++$i) {
                $rows[] = (object)['number' => $group->first_row + $i, 'values' => []];
            }
            $records[] = (object)['number' => $group->number, 'pages' => '-'];
            continue;
        }
        $record = '';
        for ($page_number = 0; $page_number < $group->chunks[0]->page_count; ++$page_number) {
            $page_information = static fn(int $column): object => $group->chunks[$column]->data_pages[$page_number];
            if ($query->condition !== null && !isset(zone_values($query->condition, $page_information)[TV_TRUE])) {
                $counts['pages_skipped'] += count($query->needed);
                $record .= 's';
                continue;
            }
            $page = $group->chunks[0]->data_pages[$page_number];
            $counts['rows_scanned'] += $page->count;
            $values = array_fill(0, $page->count, array_fill(0, count($file->schema), null));
            $read_column = static function (int $column) use ($group, $page_number, $decode, &$values): void {
                $chunk = $group->chunks[$column];
                foreach ($decode($chunk, $chunk->data_pages[$page_number]) as $i => $value) {
                    $values[$i][$column] = $value;
                }
            };
            foreach ($query->condition_columns as $column) {
                $read_column($column);
            }
            $selected = [];
            foreach ($values as $i => $row) {
                if (evaluate($query->condition, $row) === TV_TRUE) {
                    $selected[] = $i;
                }
            }
            if (!$selected && $query->remaining) {
                $counts['pages_unneeded'] += count($query->remaining);
                $record .= 'u';
            } else {
                foreach ($query->remaining as $column) {
                    $read_column($column);
                }
                foreach ($selected as $i) {
                    $rows[] = (object)['number' => $page->first_row + $i, 'values' => $values[$i]];
                }
                $record .= 'r';
            }
        }
        $records[] = (object)['number' => $group->number, 'pages' => $record];
    }
    $counts['rows_matched'] = count($rows);
    return [$counts, $records, $rows];
}

function fraction(int $numerator, int $denominator): string
{
    $first = abs($numerator);
    $second = $denominator;
    while ($second !== 0) {
        [$first, $second] = [$second, $first % $second];
    }
    $numerator = intdiv($numerator, $first);
    $denominator = intdiv($denominator, $first);
    return $denominator === 1 ? (string)$numerator : "$numerator/$denominator";
}

function aggregate_item(object $item, object $group, array $schema): string
{
    if ($item->kind === 'column') {
        return value_text($group->key, $schema[$item->column]->type);
    }
    if ($item->name === null) {
        return (string)count($group->rows);
    }
    $values = [];
    foreach ($group->rows as $row) {
        if ($row->values[$item->column] !== null) {
            $values[] = $row->values[$item->column];
        }
    }
    if ($item->function === 'COUNT') {
        return (string)($item->distinct ? count(array_unique($values, SORT_STRING)) : count($values));
    }
    if (!$values) {
        return 'NULL';
    }
    if ($item->function === 'SUM' || $item->function === 'AVG') {
        $total = 0;
        foreach ($values as $value) {
            $total += $value;
        }
        return $item->function === 'SUM' ? (string)$total : fraction($total, count($values));
    }
    $chosen = $values[0];
    foreach ($values as $value) {
        $order = compare_values($value, $chosen);
        if ($item->function === 'MIN' ? $order < 0 : $order > 0) {
            $chosen = $value;
        }
    }
    return value_text($chosen, $schema[$item->column]->type);
}

function build_result(object $query, array $rows, array $schema): array
{
    $kind = $query->group !== null ? 'grouped' : ($query->aggregate ? 'aggregate' : 'rows');
    $output = [];
    if ($kind === 'rows') {
        $arranged = $rows;
        if ($query->order !== null) {
            $column = $query->order->column;
            $direction = $query->order->descending ? -1 : 1;
            usort($arranged, static fn(object $a, object $b): int => $direction * compare_values($a->values[$column], $b->values[$column])
                ?: ($a->number <=> $b->number));
        }
        foreach ($arranged as $row) {
            $output[] = implode(',', array_map(static fn(object $item): string => value_text($row->values[$item->column], $schema[$item->column]->type), $query->items));
        }
    } else {
        if ($kind === 'aggregate') {
            $groups = [(object)['key' => null, 'rows' => $rows]];
        } else {
            $groups = [];
            foreach ($rows as $row) {
                $key = $row->values[$query->group_column];
                $encoded = serialize($key);
                $groups[$encoded] ??= (object)['key' => $key, 'rows' => []];
                $groups[$encoded]->rows[] = $row;
            }
            $groups = array_values($groups);
            usort($groups, static fn(object $a, object $b): int => compare_values($a->key, $b->key));
        }
        foreach ($groups as $group) {
            $output[] = implode(',', array_map(static fn(object $item): string => aggregate_item($item, $group, $schema), $query->items));
        }
    }
    if ($query->limit !== null) {
        $output = array_slice($output, 0, $query->limit);
    }
    return [$kind, count($rows), $output];
}

function count_text(array $counts): string
{
    return implode(' ', array_map(static fn(string $field): string => "$field {$counts[$field]}", SCAN_FIELDS));
}

function query_reports(object $file, object $input): array
{
    $results = $stats = [];
    $totals = array_fill_keys(SCAN_FIELDS, 0);
    $errors = $checks = 0;
    foreach ($input->queries as $index => $line) {
        $number = $index + 1;
        $query = (new QueryParser($line))->parse();
        $error = check_query($query, $file->schema);
        if ($error !== null) {
            $results[] = $stats[] = "query $number error $error";
            ++$errors;
            continue;
        }
        [$counts, $records, $rows] = scan_file($file, $query);
        [$kind, $matched, $output] = build_result($query, $rows, $file->schema);
        $original = [];
        foreach ($input->table as $row => $values) {
            if (evaluate($query->condition, $values) === TV_TRUE) {
                $original[] = (object)['number' => $row, 'values' => $values];
            }
        }
        $agrees = [$kind, $matched, $output] === build_result($query, $original, $input->schema);
        $check = $agrees ? 'ok' : 'mismatch';
        $checks += (int)$agrees;
        $results[] = "query $number $kind matched $matched output " . count($output);
        $results[] = 'columns ' . implode(',', $query->headers);
        array_push($results, ...$output);
        $needed = $query->needed ? implode(',', array_map(static fn(int $c): string => $file->schema[$c]->name, $query->needed)) : '-';
        $stats[] = "query $number columns $needed " . count_text($counts) . " check $check";
        foreach ($records as $record) {
            $stats[] = "query $number row_group {$record->number} " . (($record->skipped ?? false) ? 'skipped' : "pages {$record->pages}");
        }
        foreach (SCAN_FIELDS as $field) {
            $totals[$field] += $counts[$field];
        }
    }
    $stats[] = 'total queries ' . count($input->queries) . " errors $errors " . count_text($totals) . " checks_ok $checks";
    return [$results, $stats];
}

function recover(string $bytes): array
{
    $file = parse_file($bytes);
    $table = array_fill(0, $file->row_count, array_fill(0, count($file->schema), RecoveryValue::LOST));
    $lines = ['file bytes ' . strlen($bytes) . " rows {$file->row_count} columns " . count($file->schema)
        . ' row_groups ' . count($file->groups), ...column_lines($file->schema)];
    $pages = $damaged = $lost_pages = $lost_cells = 0;
    foreach ($file->groups as $group) {
        foreach ($group->chunks as $chunk) {
            $dictionary = [];
            $dictionary_damaged = false;
            foreach ($chunk->pages as $page) {
                ++$pages;
                $computed = adler32(body_of($file, $page));
                $bad = $computed !== $page->checksum;
                if ($bad) {
                    ++$damaged;
                    $label = $page->kind === 1 ? 'dict' : $page->number;
                    $lines[] = "damaged {$group->number} {$chunk->column->name} $label offset {$page->offset} stored "
                        . checksum_text($page->checksum) . ' computed ' . checksum_text($computed);
                }
                if ($page->kind === 1) {
                    $dictionary_damaged = $bad;
                    if (!$bad) {
                        $dictionary = decode_dictionary($file, $chunk);
                    }
                    continue;
                }
                $reason = $bad ? 'checksum' : ($page->method === 1 && $dictionary_damaged ? 'dictionary' : null);
                if ($reason !== null) {
                    ++$lost_pages;
                    $lost_cells += $page->count;
                    $lines[] = "lost {$group->number} {$chunk->column->name} {$page->number} rows {$page->count} reason $reason";
                } else {
                    foreach (decode_page($file, $chunk, $page, $dictionary) as $index => $value) {
                        $table[$page->first_row + $index][$chunk->column->number] = $value;
                    }
                }
            }
        }
    }
    $lines[] = "summary pages $pages damaged $damaged lost_pages $lost_pages lost_cells $lost_cells recovered_cells "
        . ($file->row_count * count($file->schema) - $lost_cells);
    $recovered = [implode(',', array_map(static fn(object $column): string => $column->name, $file->schema))];
    foreach ($table as $row) {
        $fields = [];
        foreach ($row as $column => $value) {
            $fields[] = $value === RecoveryValue::LOST ? '?' : value_text($value, $file->schema[$column]->type, true);
        }
        $recovered[] = implode(',', $fields);
    }
    return [$lines, $recovered];
}

function main(): void
{
    [$schema, $table, $options, $queries, $damaged] = read_inputs();
    $input = (object)compact('schema', 'table', 'options', 'queries', 'damaged');
    [$bytes, $encoding_report] = write_table($input);
    $file = parse_file($bytes);
    $verification = metadata($file, $table);
    [$results, $stats] = query_reports($file, $input);
    [$recovery, $recovered] = recover($damaged);
    write_files(['file.hex' => str_split(bin2hex($bytes), 64), 'metadata.txt' => $verification,
        'encoding_report.csv' => $encoding_report, 'query_results.txt' => $results,
        'query_stats.txt' => $stats, 'recovery.txt' => $recovery, 'recovered.csv' => $recovered]);
}

main();
