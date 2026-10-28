<?php

function isName(string $s): bool
{
    return (
        preg_match('/^[a-z][a-z0-9_]*$/D', $s) === 1
        && !in_array($s, ['bounds', 'integer', 'binary', 'free', 'inf'], true)
    );
}

function expression(array $words): ?array
{
    $i = 0;
    $sign = 1;
    $terms = [];
    if (($words[0] ?? null) === '-') {
        $i = 1;
        $sign = -1;
    }
    while ($i < count($words)) {
        $coefficient = readNumber($words[$i]);
        if ($coefficient !== null) {
            if (!isset($words[$i + 1]) || !isName($words[$i + 1]))
                return null;
            $name = $words[$i + 1];
            $i += 2;
        } elseif (isName($words[$i])) {
            $name = $words[$i++];
            $coefficient = new Rational(1);
        } else
            return null;
        $terms[] = [$name, $coefficient->scale($sign)];
        if ($i === count($words))
            return $terms;
        if (!in_array($words[$i], ['+', '-'], true))
            return null;
        $sign = $words[$i++] === '+' ? 1 : -1;
    }
    return null;
}

function namedExpression(array $words): ?array
{
    if (count($words) < 2 || !str_ends_with($words[0], ':'))
        return null;
    $name = substr($words[0], 0, -1);
    $terms = expression(array_slice($words, 1));
    return isName($name) && $terms !== null ? [$name, $terms] : null;
}

function constraintLine(array $w, int $line): ?object
{
    $n = count($w);
    if ($n < 4 || !in_array($w[$n - 2], ['<=', '>=', '='], true))
        return null;
    $rhs = readNumber($w[$n - 1], true);
    $named = namedExpression(array_slice($w, 0, -2));
    return (
        $rhs === null || $named === null
            ? null
            : (object) [
                'line' => $line,
                'name' => $named[0],
                'terms' => $named[1],
                'comparison' => $w[$n - 2],
                'rhs' => $rhs,
            ]
    );
}

function boundLine(array $w, int $line): ?array
{
    if (count($w) === 2 && isName($w[0]) && $w[1] === 'free')
        return [$line, $w[0], 'both', null, null];
    if (count($w) === 3 && isName($w[0])) {
        [$name, $op, $word] = $w;
        $v = readNumber($word, true);
        if ($op === '>=' && ($v !== null || $word === '-inf'))
            return [$line, $name, 'lower', $v, null];
        if ($op === '<=' && ($v !== null || $word === 'inf'))
            return [$line, $name, 'upper', null, $v];
        if ($op === '=' && $v !== null)
            return [$line, $name, 'both', $v, $v];
    }
    if (count($w) === 5 && $w[1] === '<=' && $w[3] === '<=' && isName($w[2])) {
        $lo = readNumber($w[0], true);
        $hi = readNumber($w[4], true);
        if (($lo !== null || $w[0] === '-inf') && ($hi !== null || $w[4] === 'inf'))
            return [$line, $w[2], 'both', $lo, $hi];
    }
    return null;
}

function parseBlock(string $name, array $body, int $endLine): object
{
    $r = (object) [
        'name' => $name,
        'error' => null,
        'direction' => null,
        'objective' => null,
        'constraints' => [],
        'bounds' => [],
        'integers' => [],
        'binaries' => [],
    ];
    $state = 'A';
    foreach ($body as [$line, $text]) {
        $w = explode(' ', $text);
        $accepted = false;
        switch ($state) {
            case 'A':
                if (in_array($text, ['maximize', 'minimize'], true)) {
                    $r->direction = $text;
                    $state = 'B';
                    $accepted = true;
                }
                break;
            case 'B':
                $named = namedExpression($w);
                if ($named !== null) {
                    $r->objective = $named[1];
                    $state = 'C';
                    $accepted = true;
                }
                break;
            case 'C':
                if ($text === 'subject to') {
                    $state = 'D';
                    $accepted = true;
                }
                break;
            case 'D':
            case 'E':
                if ($state === 'E' && in_array($text, ['bounds', 'integer', 'binary'], true)) {
                    $state = ['bounds' => 'F', 'integer' => 'G', 'binary' => 'H'][$text];
                    $accepted = true;
                } else {
                    $c = constraintLine($w, $line);
                    if ($c !== null) {
                        $r->constraints[] = $c;
                        $state = 'E';
                        $accepted = true;
                    }
                }
                break;
            case 'F':
                if (in_array($text, ['integer', 'binary'], true)) {
                    $state = $text === 'integer' ? 'G' : 'H';
                    $accepted = true;
                } else {
                    $b = boundLine($w, $line);
                    if ($b !== null) {
                        $r->bounds[] = $b;
                        $accepted = true;
                    }
                }
                break;
            case 'G':
            case 'H':
                if ($state === 'G' && $text === 'binary') {
                    $state = 'H';
                    $accepted = true;
                } elseif (array_all($w, isName(...))) {
                    if ($state === 'G')
                        $r->integers[] = [$line, $w];
                    else
                        $r->binaries[] = [$line, $w];
                    $accepted = true;
                }
                break;
        }
        if (!$accepted) {
            $r->error = [$line, 'syntax error'];
            return $r;
        }
    }
    if (in_array($state, ['A', 'B', 'C', 'D'], true))
        $r->error = [$endLine, 'syntax error'];
    return $r;
}

function readModels(): array
{
    $models = [];
    $name = null;
    $body = [];
    foreach (file('input/models.lp', FILE_IGNORE_NEW_LINES) as $i => $line) {
        if ($line === '' || $line[0] === '#')
            continue;
        if ($name === null) {
            $name = explode(' ', $line)[1];
            $body = [];
        } elseif ($line === 'end') {
            $models[] = parseBlock($name, $body, $i + 1);
            $name = null;
        } else
            $body[] = [$i + 1, $line];
    }
    return $models;
}

function readSettings(): object
{
    $lines = file('input/params.txt', FILE_IGNORE_NEW_LINES);
    $r = (object) [
        'level' => (int) explode(' ', $lines[0])[1],
        'limit' => (int) explode(' ', $lines[1])[1],
        'logs' => [],
        'limits' => [],
    ];
    foreach (array_slice($lines, 2) as $line) {
        [$kind, $name, $value] = explode(' ', $line);
        if ($kind === 'log')
            $r->logs[$name] = (int) $value;
        else
            $r->limits[$name] = (int) $value;
    }
    return $r;
}
