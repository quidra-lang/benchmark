<?php

class TreeAttribute
{
    public function __construct(public int $index, public string $name, public bool $integer, public array $values)
    {
    }
}

class DataRow
{
    public function __construct(public string $id, public array $values, public int $label)
    {
    }
}

function read_lines(string $path): array
{
    return file($path, FILE_IGNORE_NEW_LINES);
}

function load_dataset(string $directory): array
{
    $schema = array_map(fn($line) => explode(' ', $line), read_lines($directory . '/schema.txt'));
    $classFields = array_pop($schema);
    $classes = array_slice($classFields, 2);
    $attributes = [];
    foreach ($schema as $index => $fields) {
        $attributes[] = new TreeAttribute($index, $fields[1], $fields[2] === 'INT', array_slice($fields, 3));
    }
    $readRows = function ($name) use ($directory, $attributes, $classes) {
        $rows = [];
        foreach (array_slice(read_lines($directory . '/' . $name . '.csv'), 1) as $line) {
            $fields = explode(',', $line);
            $values = [];
            foreach ($attributes as $attribute) {
                $text = $fields[$attribute->index + 1];
                $values[] = $text === '?' ? null : ($attribute->integer ? (int) $text : array_search($text, $attribute->values, true));
            }
            $rows[] = new DataRow($fields[0], $values, array_search($fields[count($fields) - 1], $classes, true));
        }
        return $rows;
    };
    $settings = [];
    foreach (read_lines($directory . '/params.txt') as $line) {
        $fields = explode(' ', $line);
        $key = strtolower(array_shift($fields));
        $values = array_map('intval', $fields);
        $settings[$key] = $key === 'curve' ? $values : $values[0];
    }
    return ['attributes' => $attributes, 'target' => $classFields[1], 'classes' => $classes,
        'settings' => $settings, 'train' => $readRows('train'), 'validation' => $readRows('validation'), 'test' => $readRows('test')];
}
