<?php

function firstOf(array $symbols, array $nullable, array $first): object
{
    $terminals = [];
    foreach ($symbols as $symbol) {
        if (!isNonterminal($symbol)) {
            $terminals[$symbol] = true;
            return (object) ['terminals' => $terminals, 'nullable' => false];
        }
        foreach ($first[$symbol] as $terminal => $value) $terminals[$terminal] = true;
        if (!$nullable[$symbol]) return (object) ['terminals' => $terminals, 'nullable' => false];
    }
    return (object) ['terminals' => $terminals, 'nullable' => true];
}

function addAll(array &$target, array $values): bool
{
    $changed = false;
    foreach ($values as $value => $present) {
        if (!isset($target[$value])) {
            $target[$value] = true;
            $changed = true;
        }
    }
    return $changed;
}

function computeSets(object $grammar): object
{
    $nullable = $first = $follow = [];
    foreach ($grammar->order as $name) {
        $nullable[$name] = false;
        $first[$name] = [];
        $follow[$name] = [];
    }
    $follow[$grammar->start]['$'] = true;
    $passes = (object) ['nullable' => 0, 'first' => 0, 'follow' => 0];
    do {
        $changed = false;
        $passes->nullable++;
        foreach ($grammar->order as $name) {
            if ($nullable[$name]) continue;
            foreach ($grammar->rules[$name] as $right) {
                $all = true;
                foreach ($right as $symbol) if (!isNonterminal($symbol) || !$nullable[$symbol]) {
                    $all = false;
                    break;
                }
                if ($all) {
                    $nullable[$name] = true;
                    $changed = true;
                    break;
                }
            }
        }
    } while ($changed);
    do {
        $changed = false;
        $passes->first++;
        foreach ($grammar->order as $name) {
            foreach ($grammar->rules[$name] as $right) {
                if (addAll($first[$name], firstOf($right, $nullable, $first)->terminals)) $changed = true;
            }
        }
    } while ($changed);
    do {
        $changed = false;
        $passes->follow++;
        foreach ($grammar->order as $name) {
            foreach ($grammar->rules[$name] as $right) {
                foreach ($right as $index => $symbol) {
                    if (!isNonterminal($symbol)) continue;
                    $suffix = firstOf(array_slice($right, $index + 1), $nullable, $first);
                    if (addAll($follow[$symbol], $suffix->terminals)) $changed = true;
                    if ($suffix->nullable && addAll($follow[$symbol], $follow[$name])) $changed = true;
                }
            }
        }
    } while ($changed);
    return (object) compact('nullable', 'first', 'follow', 'passes');
}
