<?php

function isNonterminal(string $symbol): bool
{
    return str_starts_with($symbol, '<') && str_ends_with($symbol, '>');
}

function notation(array $symbols): string
{
    return $symbols ? implode(' ', $symbols) : '%empty';
}

function productionText(string $left, array $right): string
{
    return $left . ' -> ' . notation($right);
}

function copyGrammar(object $grammar): object
{
    return (object) ['start' => $grammar->start, 'order' => $grammar->order, 'rules' => $grammar->rules];
}

function tokenize(string $line): array
{
    $tokens = [];
    $position = 0;
    while ($position < strlen($line)) {
        if ($line[$position] === ' ') {
            $position++;
            continue;
        }
        if ($line[$position] === '#') break;
        $rest = substr($line, $position);
        $kind = 'invalid';
        $text = $value = '';
        if (preg_match('/\A<[A-Za-z][A-Za-z0-9_]*>/', $rest, $match)) {
            $kind = 'nonterminal';
            $text = $value = $match[0];
        } elseif (preg_match('/\A"([^ "]+)"/', $rest, $match)) {
            $kind = 'quoted';
            $text = $match[0];
            $value = $match[1];
        } elseif (preg_match('/\A[A-Za-z][A-Za-z0-9_]*/', $rest, $match)) {
            $kind = 'word';
            $text = $value = $match[0];
        } elseif (str_starts_with($rest, '::=')) {
            $kind = 'definition';
            $text = $value = '::=';
        } elseif ($rest[0] === '|') {
            $kind = 'separator';
            $text = $value = '|';
        } elseif (preg_match('/\A%([A-Za-z]+)/', $rest, $match) && in_array($match[1], ['empty', 'start', 'token'], true)) {
            $kind = $match[1];
            $text = $value = $match[0];
        }
        $tokens[] = (object) ['kind' => $kind, 'value' => $value, 'start' => $position + 1, 'end' => $position + strlen($text)];
        if ($kind === 'invalid') break;
        $position += strlen($text);
    }
    return $tokens;
}

function syntaxError(array $tokens): ?int
{
    $state = 'begin';
    foreach ($tokens as $token) {
        $kind = $token->kind;
        $next = null;
        if ($state === 'begin') {
            if ($kind === 'nonterminal') $next = 'definition';
            elseif ($kind === 'separator') $next = 'alternative';
            elseif ($kind === 'start') $next = 'start_symbol';
            elseif ($kind === 'token') $next = 'declaration';
        } elseif ($state === 'definition') {
            if ($kind === 'definition') $next = 'alternative';
        } elseif ($state === 'alternative') {
            if (in_array($kind, ['nonterminal', 'word', 'quoted'], true)) $next = 'symbols';
            elseif ($kind === 'empty') $next = 'empty';
        } elseif ($state === 'symbols') {
            if (in_array($kind, ['nonterminal', 'word', 'quoted'], true)) $next = 'symbols';
            elseif ($kind === 'separator') $next = 'alternative';
        } elseif ($state === 'empty') {
            if ($kind === 'separator') $next = 'alternative';
        } elseif ($state === 'start_symbol') {
            if ($kind === 'nonterminal') $next = 'complete';
        } elseif ($state === 'declaration' || $state === 'words') {
            if ($kind === 'word') $next = 'words';
        }
        if ($next === null) return $token->start;
        $state = $next;
    }
    return in_array($state, ['symbols', 'empty', 'complete', 'words'], true) ? null : $tokens[count($tokens) - 1]->end + 1;
}

function parseGrammar(array $lines): object
{
    $grammar = (object) ['start' => null, 'order' => [], 'rules' => []];
    $declared = [];
    $wordLines = [];
    $diagnostics = [];
    $hasDeclarations = false;
    $attached = null;
    foreach ($lines as $index => $line) {
        $number = $index + 1;
        $tokens = tokenize($line);
        if (!$tokens) continue;
        $column = syntaxError($tokens);
        if ($column !== null) {
            $diagnostics[] = 'line ' . $number . ': syntax error at column ' . $column;
            $attached = null;
            continue;
        }
        $first = $tokens[0];
        if ($first->kind === 'start') {
            if ($grammar->start === null) $grammar->start = $tokens[1]->value;
            else $diagnostics[] = 'line ' . $number . ': duplicate %start';
            $attached = null;
            continue;
        }
        if ($first->kind === 'token') {
            $hasDeclarations = true;
            foreach (array_slice($tokens, 1) as $token) $declared[$token->value] = true;
            $attached = null;
            continue;
        }
        $offset = 1;
        if ($first->kind === 'nonterminal') {
            $attached = $first->value;
            if (!isset($grammar->rules[$attached])) {
                $grammar->order[] = $attached;
                $grammar->rules[$attached] = [];
            }
            $offset = 2;
        } elseif ($attached === null) {
            $diagnostics[] = 'line ' . $number . ': continuation without a rule';
            continue;
        }
        $alternatives = [[]];
        foreach (array_slice($tokens, $offset) as $token) {
            if ($token->kind === 'separator') $alternatives[] = [];
            elseif ($token->kind !== 'empty') $alternatives[count($alternatives) - 1][] = $token->value;
            if ($token->kind === 'word' && !isset($wordLines[$token->value])) $wordLines[$token->value] = $number;
        }
        $seen = [];
        foreach ($grammar->rules[$attached] as $right) $seen[json_encode($right)] = true;
        foreach ($alternatives as $right) {
            $key = json_encode($right);
            if (isset($seen[$key])) $diagnostics[] = 'line ' . $number . ': duplicate alternative ' . productionText($attached, $right);
            else {
                $seen[$key] = true;
                $grammar->rules[$attached][] = $right;
            }
        }
    }
    if ($grammar->start === null) $grammar->start = $grammar->order[0];
    return (object) compact('grammar', 'declared', 'hasDeclarations', 'wordLines', 'diagnostics');
}
