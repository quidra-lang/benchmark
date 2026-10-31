<?php
namespace LinkAnalysis;

function read_lines(string $path): array
{
    return file($path, FILE_IGNORE_NEW_LINES);
}

function read_input(): array
{
    $pages = $records = $queries = $settings = [];
    foreach (array_slice(read_lines('input/pages.csv'), 1) as $line) {
        [$id, $host, $title] = explode(',', $line);
        $pages[] = ['id' => (int)$id, 'host' => $host, 'title' => $title, 'words' => explode(' ', $title)];
    }
    usort($pages, fn($a, $b) => $a['id'] <=> $b['id']);
    foreach (array_slice(read_lines('input/links.csv'), 1) as $index => $line) {
        [$source, $target] = array_map('intval', explode(',', $line));
        $records[] = ['line' => $index + 2, 'source' => $source, 'target' => $target];
    }
    foreach (read_lines('input/queries.txt') as $index => $line) {
        [$words, $seeds] = explode(' | ', $line);
        $queries[] = ['number' => $index + 1, 'words' => explode(' ', $words), 'seeds' => array_map('intval', explode(' ', $seeds))];
    }
    foreach (read_lines('input/params.txt') as $line) {
        $values = explode(' ', $line);
        $key = array_shift($values);
        $settings[$key] = match ($key) {
            'DAMPING_SWEEP' => array_map('floatval', $values),
            'TRUSTED' => array_map('intval', $values),
            'DAMPING', 'TOLERANCE', 'SPAM_THRESHOLD' => (float)$values[0],
            default => (int)$values[0],
        };
    }
    return [$pages, $records, $queries, $settings];
}
