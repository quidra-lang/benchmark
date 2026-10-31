<?php

function expressions(string $text): array
{
    $text = preg_replace('/;[^\n]*/', '', $text);
    preg_match_all('/\(|\)|[^ ()\n]+/', $text, $matches);
    $tokens = $matches[0];
    $i = 0;
    $read = function () use (&$read, &$i, $tokens): array|string {
        $token = $tokens[$i++];
        if ($token !== '(')
            return $token;
        $list = [];
        while ($tokens[$i] !== ')')
            $list[] = $read();
        ++$i;
        return $list;
    };
    $roots = [];
    while ($i < count($tokens))
        $roots[] = $read();
    return $roots;
}

function typedList(array $words): array
{
    $result = $pending = [];
    for ($i = 0; $i < count($words);) {
        if ($words[$i] === '-') {
            foreach ($pending as $name)
                $result[] = [$name, $words[$i + 1]];
            $pending = [];
            $i += 2;
        } else
            $pending[] = $words[$i++];
    }
    foreach ($pending as $name)
        $result[] = [$name, 'object'];
    return $result;
}

function atom(array $expression): array
{
    return [$expression[0], array_slice($expression, 1)];
}

function elements(array $expression, bool $empty = true): array
{
    $conjunction = $expression[0] === 'and' && array_all(array_slice($expression, 1), is_array(...));
    return $conjunction && ($empty || count($expression) > 1) ? array_slice($expression, 1) : [$expression];
}

function literal(array $expression): array
{
    return (
        $expression[0] === 'not' && count($expression) === 2 && is_array($expression[1])
            ? [false, atom($expression[1])]
            : [true, atom($expression)]
    );
}

function readDomain(string $text): object
{
    $e = expressions($text)[0];
    $d = (object) [
        'name' => $e[1][1],
        'parents' => ['object' => null],
        'typeOrder' => ['object'],
        'predicates' => [],
        'actions' => [],
    ];
    foreach (array_slice($e, 2) as $s) {
        if ($s[0] === ':types') {
            foreach (array_slice($s, 1) as $name)
                if ($name !== '-' && !array_key_exists($name, $d->parents)) {
                    $d->parents[$name] = 'object';
                    $d->typeOrder[] = $name;
                }
            foreach (typedList(array_slice($s, 1)) as [$name, $parent])
                $d->parents[$name] = $parent;
        } elseif ($s[0] === ':predicates')
            foreach (array_slice($s, 1) as $p)
                $d->predicates[$p[0]] = array_column(typedList(array_slice($p, 1)), 1);
        elseif ($s[0] === ':action') {
            $fields = [];
            for ($i = 2; $i < count($s); $i += 2)
                $fields[$s[$i]] = $s[$i + 1];
            $condition = isset($fields[':precondition'])
                ? array_map(literal(...), elements($fields[':precondition']))
                : [];
            $effects = [];
            $cost = 1;
            foreach (elements($fields[':effect'], false) as $item) {
                if ($item[0] === 'increase' && count($item) === 3 && $item[1] === ['total-cost'])
                    $cost = (int) $item[2];
                else
                    $effects[] = literal($item);
            }
            $d->actions[] = (object) [
                'name' => $s[1],
                'parameters' => typedList($fields[':parameters']),
                'condition' => $condition,
                'effects' => $effects,
                'cost' => $cost,
            ];
        }
    }
    return $d;
}

function readProblems(string $text): array
{
    $problems = [];
    foreach (expressions($text) as $e) {
        $sections = [];
        foreach (array_slice($e, 2) as $s)
            $sections[$s[0]] = array_slice($s, 1);
        $objects = [];
        foreach (typedList($sections[':objects']) as [$name, $kind])
            $objects[$name] = $kind;
        $problems[] = (object) [
            'name' => $e[1][1],
            'objects' => $objects,
            'initial' => array_map(atom(...), $sections[':init']),
            'goals' => array_map(atom(...), elements($sections[':goal'][0], false)),
        ];
    }
    return $problems;
}
