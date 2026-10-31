<?php

function preprocess(object $formula, bool $usePure): object
{
    $fixed = array_fill(0, $formula->variables + 1, null);
    $statistics = (object) ['tautologies' => 0, 'duplicateLiterals' => 0, 'unitFixed' => 0, 'unitRemoved' => 0,
        'subsumed' => 0, 'pureFixed' => 0, 'pureRemoved' => 0];
    $records = (object) ['tautology' => [], 'unit' => [], 'subsumed' => [], 'pure' => []];
    $working = [];
    $emptyClause = null;
    foreach ($formula->clauses as $index => $literals) {
        $unique = [];
        foreach ($literals as $literal) $unique[$literal] = true;
        $tautology = false;
        foreach ($literals as $literal) {
            if (isset($unique[-$literal])) {
                $tautology = true;
                break;
            }
        }
        if ($tautology) {
            $statistics->tautologies++;
            $records->tautology[] = $index + 1;
        } else {
            $statistics->duplicateLiterals += count($literals) - count($unique);
            $working[] = (object) ['number' => $index + 1, 'literals' => array_keys($unique)];
        }
    }
    while (true) {
        foreach ($working as $clause) {
            if (!$clause->literals) {
                $emptyClause = $clause->number;
                break;
            }
        }
        if ($emptyClause !== null) break;
        $unit = null;
        foreach ($working as $clause) {
            if (count($clause->literals) === 1) {
                $unit = $clause;
                break;
            }
        }
        if ($unit === null) break;
        $literal = $unit->literals[0];
        $fixed[abs($literal)] = $literal > 0;
        $statistics->unitFixed++;
        $remaining = [];
        foreach ($working as $clause) {
            if (in_array($literal, $clause->literals, true)) {
                $statistics->unitRemoved++;
                $records->unit[] = $clause->number;
            } else {
                $remaining[] = (object) ['number' => $clause->number,
                    'literals' => array_values(array_filter($clause->literals, fn($value) => $value !== -$literal))];
            }
        }
        $working = $remaining;
    }
    if ($emptyClause === null) {
        $sets = array_map(fn($clause) => array_fill_keys($clause->literals, true), $working);
        $removed = [];
        foreach ($working as $index => $clause) {
            $drop = false;
            foreach ($working as $other => $candidate) {
                if ($other === $index || count($candidate->literals) > count($clause->literals)) continue;
                if (count($candidate->literals) === count($clause->literals) && $other > $index) continue;
                $subset = true;
                foreach ($candidate->literals as $literal) {
                    if (!isset($sets[$index][$literal])) {
                        $subset = false;
                        break;
                    }
                }
                if ($subset) {
                    $drop = true;
                    break;
                }
            }
            $removed[] = $drop;
        }
        $remaining = [];
        foreach ($working as $index => $clause) {
            if (!$removed[$index]) $remaining[] = $clause;
            else {
                $statistics->subsumed++;
                $records->subsumed[] = $clause->number;
            }
        }
        $working = $remaining;
        if ($usePure) {
            while (true) {
                $present = [];
                foreach ($working as $clause) foreach ($clause->literals as $literal) $present[$literal] = true;
                $pure = [];
                foreach ($present as $literal => $value) if (!isset($present[-$literal])) $pure[$literal] = true;
                if (!$pure) break;
                foreach ($pure as $literal => $value) $fixed[abs($literal)] = $literal > 0;
                $statistics->pureFixed += count($pure);
                $remaining = [];
                foreach ($working as $clause) {
                    $drop = false;
                    foreach ($clause->literals as $literal) if (isset($pure[$literal])) {
                        $drop = true;
                        break;
                    }
                    if (!$drop) $remaining[] = $clause;
                    else {
                        $statistics->pureRemoved++;
                        $records->pure[] = $clause->number;
                    }
                }
                $working = $remaining;
            }
        }
    }
    $active = $fixedLiterals = [];
    for ($variable = 1; $variable <= $formula->variables; $variable++) {
        if ($fixed[$variable] === null) $active[] = $variable;
        else $fixedLiterals[] = $fixed[$variable] ? $variable : -$variable;
    }
    foreach (['tautology', 'unit', 'subsumed', 'pure'] as $name) sort($records->$name, SORT_NUMERIC);
    $removed = $statistics->tautologies + $statistics->unitRemoved + $statistics->subsumed + $statistics->pureRemoved;
    return (object) ['pure' => $usePure, 'fixed' => $fixed, 'fixedLiterals' => $fixedLiterals, 'active' => $active,
        'clauses' => array_map(fn($clause) => $clause->literals, $working), 'statistics' => $statistics,
        'records' => $records, 'removed' => $removed, 'emptyClause' => $emptyClause];
}
