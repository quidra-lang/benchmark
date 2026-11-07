<?php

function displayLine(object $line, string $alignment): string
{
    $text = implode(' ', $line->pieces);
    if ($line->slack <= 0) return $text;
    if ($alignment === 'justify' && !$line->last && $line->gaps > 0) {
        $quotient = intdiv($line->slack, $line->gaps);
        $remainder = $line->slack % $line->gaps;
        $result = $line->pieces[0];
        for ($index = 1; $index < count($line->pieces); $index++) {
            $result .= str_repeat(' ', $quotient + 1 + ($index - 1 < $remainder ? 1 : 0)) . $line->pieces[$index];
        }
        return $result;
    }
    if ($alignment === 'right') return str_repeat(' ', $line->slack) . $text;
    if ($alignment === 'center') return str_repeat(' ', intdiv($line->slack, 2)) . $text;
    return $text;
}

function tableRows(array $rows, string $columns): array
{
    $widths = array_fill(0, strlen($columns), 0);
    foreach ($rows as $row) {
        foreach ($row as $index => $cell) $widths[$index] = max($widths[$index], strlen($cell));
    }
    $lines = [];
    foreach ($rows as $rowNumber => $row) {
        $cells = [];
        foreach ($row as $column => $text) {
            $missing = $widths[$column] - strlen($text);
            if ($columns[$column] === 'r') $cells[] = str_repeat(' ', $missing) . $text;
            elseif ($columns[$column] === 'c') $cells[] = str_repeat(' ', intdiv($missing, 2)) . $text . str_repeat(' ', $missing - intdiv($missing, 2));
            else $cells[] = $text . str_repeat(' ', $missing);
        }
        $lines[] = rtrim(implode(' | ', $cells), ' ');
        if ($rowNumber === 0) $lines[] = implode('-+-', array_map(fn($width) => str_repeat('-', $width), $widths));
    }
    return $lines;
}

function runningHead(array $fields, array $values, int $width, int $serial): string
{
    $expanded = array_map(fn($text) => preg_replace_callback('/\{(page|pages|chapter|section)\}/', fn($match) => $values[$match[1]], $text), $fields);
    if ($serial % 2 === 0) [$expanded[0], $expanded[2]] = [$expanded[2], $expanded[0]];
    $line = array_fill(0, $width, ' ');
    $starts = [0, intdiv($width - strlen($expanded[1]), 2), $width - strlen($expanded[2])];
    for ($field = 0; $field < 3; $field++) {
        for ($index = 0; $index < strlen($expanded[$field]); $index++) $line[$starts[$field] + $index] = $expanded[$field][$index];
    }
    return rtrim(implode('', $line), ' ');
}

function pageLines(array $pages): array
{
    $lines = [];
    foreach ($pages as $page) {
        $lines[] = '--- page ' . $page->serial . ' ---';
        $lines[] = $page->header;
        $lines[] = '';
        foreach ($page->body as $line) $lines[] = $line;
        $lines[] = '';
        $lines[] = $page->footer;
    }
    return $lines;
}
