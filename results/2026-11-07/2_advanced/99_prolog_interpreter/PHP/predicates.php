<?php

const DETERMINISTIC = [
    ['true', 0],
    ['fail', 0],
    ['false', 0],
    ['=', 2],
    ['\\=', 2],
    ['==', 2],
    ['\\==', 2],
    ['var', 1],
    ['nonvar', 1],
    ['atom', 1],
    ['number', 1],
    ['integer', 1],
    ['atomic', 1],
    ['compound', 1],
    ['callable', 1],
    ['is_list', 1],
    ['is', 2],
    ['=:=', 2],
    ['=\\=', 2],
    ['<', 2],
    ['>', 2],
    ['=<', 2],
    ['>=', 2],
    ['functor', 3],
    ['arg', 3],
    ['=..', 2],
    ['copy_term', 2],
    ['atom_length', 2],
    ['atom_chars', 2],
    ['write', 1],
    ['writeq', 1],
    ['nl', 0],
];

function checkedInteger(int $value): int
{
    if ($value < -2147483648 || $value > 2147483647)
        throw new PrologFault(new Compound('evaluation_error', 'int_overflow'));
    return $value;
}

function evaluateArithmetic(mixed $term): int
{
    $term = dereference($term);
    if ($term instanceof PrologVariable)
        throw new PrologFault('instantiation_error');
    if (is_int($term))
        return $term;
    if (is_string($term))
        throw new PrologFault(typeError('evaluable', indicatorTerm([$term, 0])));
    $key = indicator($term);
    $supported = [
        ['+', 2],
        ['-', 2],
        ['*', 2],
        ['//', 2],
        ['mod', 2],
        ['rem', 2],
        ['-', 1],
        ['abs', 1],
        ['min', 2],
        ['max', 2],
    ];
    if (!in_array($key, $supported, true))
        throw new PrologFault(typeError('evaluable', indicatorTerm($key)));
    $values = [];
    foreach ($term->args as $arg)
        $values[] = evaluateArithmetic($arg);
    $name = $term->name;
    if (count($values) === 1)
        return checkedInteger($name === '-' ? -$values[0] : abs($values[0]));
    [$a, $b] = $values;
    if (in_array($name, ['//', 'mod', 'rem'], true) && $b === 0)
        throw new PrologFault(new Compound('evaluation_error', 'zero_divisor'));
    if ($name === 'mod') {
        $result = $a % $b;
        if ($result !== 0 && $result < 0 !== $b < 0)
            $result += $b;
    } else
        $result = match ($name) {
            '+' => $a + $b,
            '-' => $a - $b,
            '*' => $a * $b,
            '//' => intdiv($a, $b),
            'rem' => $a % $b,
            'min' => min($a, $b),
            'max' => max($a, $b),
        };
    return checkedInteger($result);
}

function requireInteger(mixed $t): int
{
    $t = dereference($t);
    if ($t instanceof PrologVariable)
        throw new PrologFault('instantiation_error');
    if (!is_int($t))
        throw new PrologFault(typeError('integer', $t));
    return $t;
}

function requireAtom(mixed $t): string
{
    $t = dereference($t);
    if ($t instanceof PrologVariable)
        throw new PrologFault('instantiation_error');
    if (!is_string($t))
        throw new PrologFault(typeError('atom', $t));
    return $t;
}

function requireList(mixed $t): array
{
    [$elements, $tail] = listParts($t);
    if ($tail instanceof PrologVariable)
        throw new PrologFault('instantiation_error');
    if ($tail !== '[]')
        throw new PrologFault(typeError('list', $t));
    return $elements;
}

function freshVariables(int $count): array
{
    $values = [];
    for ($i = 0; $i < $count; ++$i)
        $values[] = new PrologVariable();
    return $values;
}

function executePredicate(mixed $goal, Trail $trail, callable $output): bool
{
    [$name, $arity] = indicator($goal);
    $args = $goal instanceof Compound ? array_map(dereference(...), $goal->args) : [];
    if ($name === 'true')
        return true;
    if ($name === 'fail' || $name === 'false')
        return false;
    if ($name === '=')
        return $trail->unify($args[0], $args[1]);
    if ($name === '\\=') {
        $mark = $trail->mark();
        $r = $trail->unify($args[0], $args[1]);
        $trail->undo($mark);
        return !$r;
    }
    if ($name === '==' || $name === '\\==') {
        $r = identical($args[0], $args[1]);
        return $name === '==' ? $r : !$r;
    }
    if (in_array(
        $name,
        ['var', 'nonvar', 'atom', 'number', 'integer', 'atomic', 'compound', 'callable', 'is_list'],
        true,
    )) {
        $t = $args[0];
        return match ($name) {
            'var' => $t instanceof PrologVariable,
            'nonvar' => !$t instanceof PrologVariable,
            'atom' => is_string($t),
            'number', 'integer' => is_int($t),
            'atomic' => is_int($t) || is_string($t),
            'compound' => $t instanceof Compound,
            'callable' => is_string($t) || $t instanceof Compound,
            'is_list' => listParts($t)[1] === '[]',
        };
    }
    if ($name === 'is')
        return $trail->unify($args[0], evaluateArithmetic($args[1]));
    if (in_array($name, ['=:=', '=\\=', '<', '>', '=<', '>='], true)) {
        $a = evaluateArithmetic($args[0]);
        $b = evaluateArithmetic($args[1]);
        return match ($name) {
            '=:=' => $a === $b,
            '=\\=' => $a !== $b,
            '<' => $a < $b,
            '>' => $a > $b,
            '=<' => $a <= $b,
            '>=' => $a >= $b,
        };
    }
    if ($name === 'functor') {
        [$term, $functor, $count] = $args;
        if (!$term instanceof PrologVariable) {
            if ($term instanceof Compound)
                return $trail->unify($functor, $term->name) && $trail->unify($count, count($term->args));
            return $trail->unify($functor, $term) && $trail->unify($count, 0);
        }
        if ($functor instanceof PrologVariable || $count instanceof PrologVariable)
            throw new PrologFault('instantiation_error');
        if ($functor instanceof Compound)
            throw new PrologFault(typeError('atomic', $functor));
        if (!is_int($count))
            throw new PrologFault(typeError('integer', $count));
        if ($count < 0)
            throw new PrologFault(domainError('not_less_than_zero', $count));
        if ($count > 255)
            throw new PrologFault(new Compound('representation_error', 'max_arity'));
        if ($count === 0)
            return $trail->unify($term, $functor);
        if (is_int($functor))
            throw new PrologFault(typeError('atom', $functor));
        return $trail->unify($term, new Compound($functor, ...freshVariables($count)));
    }
    if ($name === 'arg') {
        [$n, $term, $value] = $args;
        if ($n instanceof PrologVariable || $term instanceof PrologVariable)
            throw new PrologFault('instantiation_error');
        if (!is_int($n))
            throw new PrologFault(typeError('integer', $n));
        if (!$term instanceof Compound)
            throw new PrologFault(typeError('compound', $term));
        return $n >= 1 && $n <= count($term->args) && $trail->unify($term->args[$n - 1], $value);
    }
    if ($name === '=..') {
        [$term, $sequence] = $args;
        if ($term instanceof Compound)
            return $trail->unify(makeList([$term->name, ...$term->args]), $sequence);
        if (!$term instanceof PrologVariable)
            return $trail->unify(makeList([$term]), $sequence);
        $elements = requireList($sequence);
        if (!$elements)
            throw new PrologFault(domainError('non_empty_list', '[]'));
        $head = dereference($elements[0]);
        if ($head instanceof PrologVariable)
            throw new PrologFault('instantiation_error');
        if (count($elements) === 1) {
            if ($head instanceof Compound)
                throw new PrologFault(typeError('atomic', $head));
            return $trail->unify($term, $head);
        }
        if (!is_string($head))
            throw new PrologFault(typeError('atom', $head));
        if (count($elements) > 256)
            throw new PrologFault(new Compound('representation_error', 'max_arity'));
        return $trail->unify($term, new Compound($head, ...array_slice($elements, 1)));
    }
    if ($name === 'copy_term')
        return $trail->unify(copyTerm($args[0]), $args[1]);
    if ($name === 'atom_length') {
        $atom = requireAtom($args[0]);
        if (!$args[1] instanceof PrologVariable && !is_int($args[1]))
            throw new PrologFault(typeError('integer', $args[1]));
        return $trail->unify(strlen($atom), $args[1]);
    }
    if ($name === 'atom_chars') {
        [$atom, $sequence] = $args;
        if (!$atom instanceof PrologVariable) {
            $atom = requireAtom($atom);
            return $trail->unify($sequence, makeList(str_split($atom)));
        }
        $elements = requireList($sequence);
        $characters = '';
        foreach ($elements as $e) {
            $c = dereference($e);
            if ($c instanceof PrologVariable)
                throw new PrologFault('instantiation_error');
            if (!is_string($c) || strlen($c) !== 1)
                throw new PrologFault(typeError('character', $c));
            $characters .= $c;
        }
        return $trail->unify($atom, $characters);
    }
    if ($name === 'write' || $name === 'writeq') {
        $output($args[0], $name === 'writeq');
        return true;
    }
    $output(null, false);
    return true;
}
