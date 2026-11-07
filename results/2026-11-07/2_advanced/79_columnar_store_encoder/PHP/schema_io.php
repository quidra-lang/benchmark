<?php
declare(strict_types=1);

function leap(int $year): bool
{
    return $year % 4 === 0 && ($year % 100 !== 0 || $year % 400 === 0);
}

function month_lengths(int $year): array
{
    return [31, leap($year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
}

function before_year(int $year): int
{
    $previous = $year - 1;
    return 365 * $previous + intdiv($previous, 4) - intdiv($previous, 100) + intdiv($previous, 400);
}

function day_number(string $text): int
{
    [$year, $month, $day] = array_map('intval', explode('-', $text));
    $result = before_year($year) - before_year(1970) + $day - 1;
    $lengths = month_lengths($year);
    for ($i = 0; $i < $month - 1; ++$i) {
        $result += $lengths[$i];
    }
    return $result;
}

function date_text(int $value): string
{
    $year = 1970;
    while ($value < 0) {
        --$year;
        $value += leap($year) ? 366 : 365;
    }
    while ($value >= (leap($year) ? 366 : 365)) {
        $value -= leap($year) ? 366 : 365;
        ++$year;
    }
    $lengths = month_lengths($year);
    $month = 0;
    while ($value >= $lengths[$month]) {
        $value -= $lengths[$month++];
    }
    return sprintf('%04d-%02d-%02d', $year, $month + 1, $value + 1);
}

function convert(string $text, string $type): mixed
{
    if ($text === '') {
        return null;
    }
    return match ($type) {
        'DATE' => day_number($text), 'INT' => (int)$text, 'BOOL' => $text === 'true', default => $text
    };
}

function value_text(mixed $value, string $type, bool $recovered = false): string
{
    if ($value === null) {
        return $recovered ? '' : 'NULL';
    }
    return match ($type) {
        'DATE' => date_text($value), 'BOOL' => $value ? 'true' : 'false', default => (string)$value
    };
}

function read_inputs(): array
{
    $lines = static fn(string $name): array => file('input/' . $name, FILE_IGNORE_NEW_LINES);
    $schema = [];
    foreach ($lines('schema.txt') as $number => $line) {
        [$name, $type, $nullability] = explode(' ', $line);
        $schema[] = (object)['name' => $name, 'type' => $type, 'nullable' => $nullability === 'NULLABLE', 'number' => $number];
    }
    $table = [];
    foreach (array_slice($lines('table.csv'), 1) as $line) {
        $row = [];
        foreach (explode(',', $line) as $index => $field) {
            $row[] = convert($field, $schema[$index]->type);
        }
        $table[] = $row;
    }
    $options = ['encodings' => []];
    foreach ($lines('options.txt') as $line) {
        $fields = explode(' ', $line);
        if ($fields[0] === 'encoding') {
            $options['encodings'][$fields[1]] = $fields[2];
        } else {
            $options[$fields[0]] = (int)$fields[1];
        }
    }
    return [$schema, $table, $options, $lines('queries.txt'), hex2bin(implode('', $lines('damaged.hex')))];
}

function write_files(array $files): void
{
    if (!is_dir('output')) {
        mkdir('output');
    }
    foreach ($files as $name => $lines) {
        file_put_contents('output/' . $name, implode("\n", $lines) . ($lines ? "\n" : ''));
    }
}
