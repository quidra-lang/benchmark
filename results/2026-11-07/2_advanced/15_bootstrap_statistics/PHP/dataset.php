<?php

namespace Bootstrap;

class Group
{
    public array $sample = [];
    public array $estimates = [];
    public array $ordinary = [];
    public array $summaries = [];
    public array $balancedSummaries = [];

    public function __construct(public int $number, public string $name)
    {
    }
}

class Pair
{
    public string $name;
    public array $estimates = [];
    public array $values = [];
    public array $summaries = [];
    public array $extremes = [];

    public function __construct(public Group $first, public Group $second, public int $number)
    {
        $this->name = $first->name . '-' . $second->name;
    }
}

function hundredths(string $text): int
{
    [$whole, $fraction] = array_pad(explode('.', $text, 2), 2, '');
    return (int) $whole * 100 + (int) str_pad($fraction, 2, '0');
}

function load_dataset(string $directory): array
{
    $groups = [];
    $byName = [];
    foreach (array_slice(file($directory . '/samples.csv', FILE_IGNORE_NEW_LINES), 1) as $line) {
        [$name, $value] = explode(',', $line);
        $key = '#' . $name;
        if (!isset($byName[$key])) {
            $group = new Group(count($groups), $name);
            $byName[$key] = $group;
            $groups[] = $group;
        }
        $byName[$key]->sample[] = hundredths($value);
    }
    $before = [];
    $after = [];
    $differences = [];
    foreach (array_slice(file($directory . '/paired.csv', FILE_IGNORE_NEW_LINES), 1) as $line) {
        [$subject, $first, $second] = explode(',', $line);
        $b = hundredths($first);
        $a = hundredths($second);
        $before[] = $b;
        $after[] = $a;
        $differences[] = $a - $b;
    }
    $settings = [];
    $pairs = [];
    foreach (file($directory . '/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $fields = explode(' ', $line);
        $key = array_shift($fields);
        if ($key === 'compare') {
            $pairs[] = new Pair($byName['#' . $fields[0]], $byName['#' . $fields[1]], count($pairs));
        } elseif ($key === 'power') {
            [$settings['power_sims'], $settings['power_perms']] = array_map('intval', $fields);
        } else {
            $settings[$key] = (int) $fields[0];
        }
    }
    return ['groups' => $groups, 'before' => $before, 'after' => $after, 'differences' => $differences, 'settings' => $settings, 'pairs' => $pairs];
}
