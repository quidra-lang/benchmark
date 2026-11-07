<?php

function combinationIndex($parents, $assignment, $sizes)
{
    $index = 0;
    foreach ($parents as $parent) {
        $index = $index * $sizes[$parent] + $assignment[$parent];
    }
    return $index;
}

function countsFor($network, $variable, $parents)
{
    $combinations = 1;
    foreach ($parents as $parent) {
        $combinations *= $network->sizes[$parent];
    }
    $counts = array_fill(0, $combinations, array_fill(0, $network->sizes[$variable], 0));
    foreach ($network->samples as $sample) {
        $row = combinationIndex($parents, $sample, $network->sizes);
        $counts[$row][$sample[$variable]]++;
    }
    return $counts;
}

function learnedTable($counts, $alpha)
{
    $table = [];
    foreach ($counts as $row) {
        $total = 0.0;
        foreach ($row as $count) {
            $total += $count + $alpha;
        }
        $table[] = array_map(fn($count) => ($count + $alpha) / $total, $row);
    }
    return $table;
}

function logLikelihood($counts, $table)
{
    $total = 0.0;
    foreach ($counts as $row => $values) {
        foreach ($values as $state => $count) {
            if ($count !== 0) {
                $total += $count * log($table[$row][$state]);
            }
        }
    }
    return $total;
}

function parameterCount($counts)
{
    return (count($counts[0]) - 1) * count($counts);
}

function familyScore($network, $variable, $parents)
{
    sort($parents, SORT_NUMERIC);
    $counts = countsFor($network, $variable, $parents);
    $learned = learnedTable($counts, $network->params['alpha']);
    return logLikelihood($counts, $learned) - parameterCount($counts) * log(count($network->samples)) / 2;
}
