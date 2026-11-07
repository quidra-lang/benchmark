<?php

function inputLines($name)
{
    return file('input/' . $name, FILE_IGNORE_NEW_LINES);
}

function readNetwork()
{
    $source = array_values(array_filter(inputLines('network.txt'), fn($line) => $line !== '' && $line[0] !== '#'));
    $variables = [];
    $names = [];
    for ($index = 0; $index < count($source); $index++) {
        $fields = explode(' ', $source[$index]);
        if ($fields[0] === 'VARIABLE') {
            $names[$fields[1]] = count($variables);
            $variables[] = (object)['name' => $fields[1], 'states' => array_slice($fields, 2), 'parents' => [], 'given' => null];
        } elseif ($fields[0] === 'PARENTS') {
            $parents = [];
            foreach (array_slice($fields, 2) as $name) {
                $parents[] = $names[$name];
            }
            $variables[$names[$fields[1]]]->parents = $parents;
        } else {
            $variable = $variables[$names[$fields[1]]];
            $count = 1;
            foreach ($variable->parents as $parent) {
                $count *= count($variables[$parent]->states);
            }
            $variable->given = [];
            for ($row = 0; $row < $count; $row++) {
                $variable->given[] = array_map('floatval', explode(' ', $source[++$index]));
            }
        }
    }
    return (object)['variables' => $variables, 'names' => $names,
        'sizes' => array_map(fn($variable) => count($variable->states), $variables)];
}

function readInputs()
{
    $network = readNetwork();
    $network->stateNames = [];
    foreach ($network->variables as $variable) {
        $network->stateNames[] = array_flip($variable->states);
    }
    $source = inputLines('samples.csv');
    $columns = array_map(fn($name) => $network->names[$name], explode(',', $source[0]));
    $samples = [];
    foreach (array_slice($source, 1) as $line) {
        $values = explode(',', $line);
        $assignment = array_fill(0, count($network->variables), 0);
        foreach ($columns as $column => $variable) {
            $assignment[$variable] = $network->stateNames[$variable][$values[$column]];
        }
        $samples[] = $assignment;
    }
    $settings = array_map(fn($line) => explode(' ', $line), inputLines('params.txt'));
    $network->samples = $samples;
    $network->params = ['alpha' => (float)$settings[0][1], 'method' => strtolower($settings[1][1]),
        'order' => array_map(fn($name) => $network->names[$name], array_slice($settings[2], 1)),
        'limit' => (int)$settings[3][1], 'seed' => (int)$settings[4][1]];
    for ($index = 5; $index < count($settings); $index++) {
        $network->variables[$network->names[$settings[$index][1]]]->source = $settings[$index][2];
    }
    $network->queries = inputLines('queries.txt');
    return $network;
}
