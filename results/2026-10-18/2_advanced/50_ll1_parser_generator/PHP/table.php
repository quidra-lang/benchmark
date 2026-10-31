<?php

function numberProductions(object $grammar): array
{
    $productions = [];
    foreach ($grammar->order as $left) {
        foreach ($grammar->rules[$left] as $right) $productions[] = (object) ['number' => count($productions) + 1, 'left' => $left, 'right' => $right];
    }
    return $productions;
}

function buildTable(object $grammar, object $sets): object
{
    $productions = numberProductions($grammar);
    $known = [];
    foreach ($productions as $production) foreach ($production->right as $symbol) if (!isNonterminal($symbol)) $known[$symbol] = true;
    $columns = array_map('strval', array_keys($known));
    sort($columns, SORT_STRING);
    $columns[] = '$';
    $cells = $byLeft = $choices = [];
    foreach ($grammar->order as $left) {
        $cells[$left] = [];
        foreach ($columns as $terminal) $cells[$left][$terminal] = [];
        $byLeft[$left] = [];
        $choices[$left] = [];
    }
    foreach ($productions as $production) {
        $sequence = firstOf($production->right, $sets->nullable, $sets->first);
        $reasons = [];
        foreach ($sequence->terminals as $terminal => $value) $reasons[$terminal] = 'FIRST';
        if ($sequence->nullable) {
            foreach ($sets->follow[$production->left] as $terminal => $value) if (!isset($reasons[$terminal])) $reasons[$terminal] = 'FOLLOW';
        }
        $production->reasons = $reasons;
        $byLeft[$production->left][] = $production;
        foreach ($reasons as $terminal => $reason) $cells[$production->left][$terminal][] = $production;
    }
    $conflicts = [];
    foreach ($grammar->order as $left) {
        foreach ($columns as $terminal) {
            $entries = $cells[$left][$terminal];
            if (!$entries) continue;
            $chosen = $entries[0];
            foreach ($entries as $production) if ($production->reasons[$terminal] === 'FIRST') {
                $chosen = $production;
                break;
            }
            $choices[$left][$terminal] = $chosen;
            if (count($entries) < 2) continue;
            $reasons = [];
            foreach ($entries as $production) $reasons[$production->reasons[$terminal]] = true;
            $kind = count($reasons) === 2 ? 'FIRST/FOLLOW' : (isset($reasons['FIRST']) ? 'FIRST/FIRST' : 'FOLLOW/FOLLOW');
            $conflicts[] = (object) compact('left', 'terminal', 'entries', 'chosen', 'kind');
        }
    }
    return (object) compact('productions', 'known', 'columns', 'cells', 'choices', 'conflicts', 'byLeft');
}
