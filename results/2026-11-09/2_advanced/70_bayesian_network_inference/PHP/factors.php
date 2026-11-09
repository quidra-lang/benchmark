<?php

function assignmentCount($variables, $sizes)
{
    $count = 1;
    foreach ($variables as $variable) {
        $count *= $sizes[$variable];
    }
    return $count;
}

function assignments($variables, $sizes)
{
    $assignment = array_fill(0, count($sizes), 0);
    while (true) {
        yield $assignment;
        $index = count($variables) - 1;
        while ($index >= 0) {
            $variable = $variables[$index];
            $assignment[$variable]++;
            if ($assignment[$variable] < $sizes[$variable]) {
                break;
            }
            $assignment[$variable] = 0;
            $index--;
        }
        if ($index < 0) {
            return;
        }
    }
}

function decodeAssignment($variables, $index, $sizes)
{
    $assignment = array_fill(0, count($sizes), 0);
    for ($position = count($variables) - 1; $position >= 0; $position--) {
        $variable = $variables[$position];
        $assignment[$variable] = $index % $sizes[$variable];
        $index = intdiv($index, $sizes[$variable]);
    }
    return $assignment;
}

function factorValue($factor, $assignment, $sizes)
{
    return $factor['values'][combinationIndex($factor['variables'], $assignment, $sizes)];
}

function cptFactor($network, $index)
{
    $variable = $network->variables[$index];
    $variables = array_merge([$index], $variable->parents);
    sort($variables, SORT_NUMERIC);
    $values = [];
    foreach (assignments($variables, $network->sizes) as $assignment) {
        $values[] = $variable->cpt[combinationIndex($variable->parents, $assignment, $network->sizes)][$assignment[$index]];
    }
    return ['variables' => $variables, 'values' => $values];
}

function reduceFactor($factor, $evidence, $sizes)
{
    $variables = array_values(array_filter($factor['variables'], fn($variable) => !isset($evidence[$variable])));
    $values = [];
    foreach (assignments($variables, $sizes) as $assignment) {
        foreach ($evidence as $variable => $state) {
            $assignment[$variable] = $state;
        }
        $values[] = factorValue($factor, $assignment, $sizes);
    }
    return ['variables' => $variables, 'values' => $values];
}

function multiplyFactors($first, $second, $sizes)
{
    $variables = array_values(array_unique(array_merge($first['variables'], $second['variables'])));
    sort($variables, SORT_NUMERIC);
    $values = [];
    foreach (assignments($variables, $sizes) as $assignment) {
        $values[] = factorValue($first, $assignment, $sizes) * factorValue($second, $assignment, $sizes);
    }
    return ['variables' => $variables, 'values' => $values];
}

function factorProduct($sequence, $sizes)
{
    if (!$sequence) {
        return ['variables' => [], 'values' => [1.0]];
    }
    $result = $sequence[0];
    for ($index = 1; $index < count($sequence); $index++) {
        $result = multiplyFactors($result, $sequence[$index], $sizes);
    }
    return $result;
}

function removeVariable($factor, $variable, $sizes, $maximize)
{
    $variables = array_values(array_filter($factor['variables'], fn($item) => $item !== $variable));
    $values = [];
    foreach (assignments($variables, $sizes) as $assignment) {
        $assignment[$variable] = 0;
        $value = factorValue($factor, $assignment, $sizes);
        for ($state = 1; $state < $sizes[$variable]; $state++) {
            $assignment[$variable] = $state;
            $candidate = factorValue($factor, $assignment, $sizes);
            if ($maximize) {
                if ($candidate > $value) {
                    $value = $candidate;
                }
            } else {
                $value += $candidate;
            }
        }
        $values[] = $value;
    }
    return ['variables' => $variables, 'values' => $values];
}
