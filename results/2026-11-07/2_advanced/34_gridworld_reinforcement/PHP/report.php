<?php

const POLICY_CHARACTERS = '^>v<';

function fixed(?int $value): string
{
    if ($value === null) {
        return '-';
    }
    $magnitude = abs($value);
    return ($value < 0 ? '-' : '') . intdiv($magnitude, 10000) . '.' . sprintf('%04d', $magnitude % 10000);
}

function average(int $total, int $count): string
{
    return fixed(floorDivide(10000 * $total, $count));
}

function cell(World $world, int $position): string
{
    return intdiv($position, $world->width) . ',' . ($position % $world->width);
}

function grid(World $world, callable $content, bool $separated = false): array
{
    $lines = [];
    for ($row = 0; $row < $world->height; $row++) {
        $fields = [];
        for ($column = 0; $column < $world->width; $column++) {
            $position = $row * $world->width + $column;
            $state = $world->index[$position];
            $fields[] = $state < 0 ? $world->cells[$position] : (string) $content($state, $position);
        }
        $lines[] = implode($separated ? ' ' : '', $fields);
    }
    return $lines;
}

function policyGrid(World $world, array $policy): array
{
    return grid($world, fn($state) => POLICY_CHARACTERS[$policy[$state]]);
}

function qRows(string $name, World $world, array $table, ?array $visits = null): array
{
    $lines = [];
    foreach ($world->states as $state => $position) {
        for ($action = 0; $action < 4; $action++) {
            $lines[] = $name . ',' . cell($world, $position) . ',' . ACTIONS[$action] . ',' . fixed($table[$state][$action])
                . ',' . ($visits === null ? '-' : $visits[$state][$action]);
        }
    }
    return $lines;
}

function writeReports(array $reports): void
{
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    foreach ($reports as $name => $lines) {
        file_put_contents('output/' . $name, $lines ? implode("\n", $lines) . "\n" : '');
    }
}
