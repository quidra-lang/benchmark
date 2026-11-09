<?php

function treeNode(string $symbol): object
{
    return (object) ['symbol' => $symbol, 'mark' => null, 'children' => []];
}

function parseTokens(object $grammar, object $table, object $sets, array $input): object
{
    $root = treeNode($grammar->start);
    $stack = [(object) ['symbol' => '$', 'node' => null], (object) ['symbol' => $grammar->start, 'node' => $root]];
    $trace = $leftParse = [];
    $counts = ['skip' => 0, 'pop' => 0, 'missing' => 0];
    $position = $matches = $maximumStack = 0;
    while (true) {
        $top = $stack[count($stack) - 1];
        $token = $input[$position];
        $maximumStack = max($maximumStack, count($stack));
        $step = (object) ['number' => count($trace) + 1, 'stack' => array_map(fn($entry) => $entry->symbol, $stack),
            'input' => array_map(fn($entry) => $entry->value, array_slice($input, $position)), 'top' => $top->symbol, 'token' => $token];
        if ($top->symbol === '$' && $token->value === '$') $step->action = 'accept';
        elseif ($top->symbol === '$') {
            $step->action = 'skip';
            $position++;
        } elseif (!isNonterminal($top->symbol)) {
            array_pop($stack);
            if ($top->symbol === $token->value) {
                $step->action = 'match';
                $position++;
                $matches++;
            } else {
                $step->action = 'missing';
                $top->node->mark = 'missing';
            }
        } else {
            $production = $table->choices[$top->symbol][$token->value] ?? null;
            if ($production !== null) {
                $step->action = 'predict';
                $step->production = $production;
                $leftParse[] = $production->number;
                array_pop($stack);
                $top->node->children = $production->right ? array_map('treeNode', $production->right) : [treeNode('%empty')];
                for ($index = count($production->right) - 1; $index >= 0; $index--) {
                    $stack[] = (object) ['symbol' => $production->right[$index], 'node' => $top->node->children[$index]];
                }
            } elseif ($token->value === '$' || isset($sets->follow[$top->symbol][$token->value])) {
                $step->action = 'pop';
                $top->node->mark = 'error';
                array_pop($stack);
            } else {
                $step->action = 'skip';
                $position++;
            }
        }
        if (isset($counts[$step->action])) $counts[$step->action]++;
        $trace[] = $step;
        if ($step->action === 'accept') break;
    }
    return (object) compact('trace', 'root', 'leftParse', 'counts', 'matches', 'maximumStack');
}
