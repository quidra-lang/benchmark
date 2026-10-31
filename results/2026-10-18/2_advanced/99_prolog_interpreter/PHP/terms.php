<?php

final class PrologVariable
{
    public mixed $binding = null;
}

final readonly class Compound
{
    public array $args;

    public function __construct(
        public string $name,
        mixed ...$args,
    ) {
        $this->args = $args;
    }
}

final class PrologFault extends RuntimeException
{
    public function __construct(
        public mixed $term,
    ) {
        parent::__construct();
    }
}

final class PrologBall extends RuntimeException
{
    public function __construct(
        public mixed $term,
    ) {
        parent::__construct();
    }
}

function dereference(mixed $term): mixed
{
    while ($term instanceof PrologVariable && $term->binding !== null)
        $term = $term->binding;
    return $term;
}

function indicator(mixed $term): array
{
    $term = dereference($term);
    return $term instanceof Compound ? [$term->name, count($term->args)] : [$term, 0];
}

function indicatorTerm(array $key): Compound
{
    return new Compound('/', $key[0], $key[1]);
}

function makeList(array $elements, mixed $tail = '[]'): mixed
{
    foreach (array_reverse($elements) as $e)
        $tail = new Compound('.', $e, $tail);
    return $tail;
}

function listParts(mixed $term): array
{
    $elements = [];
    $term = dereference($term);
    while ($term instanceof Compound && $term->name === '.' && count($term->args) === 2) {
        $elements[] = $term->args[0];
        $term = dereference($term->args[1]);
    }
    return [$elements, $term];
}

function copyTerms(mixed ...$terms): array
{
    $variables = [];
    $copy = function ($term) use (&$copy, &$variables): mixed {
        $term = dereference($term);
        if ($term instanceof PrologVariable)
            return $variables[spl_object_id($term)] ??= new PrologVariable();
        if ($term instanceof Compound)
            return new Compound($term->name, ...array_map($copy, $term->args));
        return $term;
    };
    return array_map($copy, $terms);
}

function copyTerm(mixed $term): mixed
{
    return copyTerms($term)[0];
}

function variablesIn(mixed ...$terms): array
{
    $result = [];
    $stack = array_reverse($terms);
    while ($stack) {
        $term = dereference(array_pop($stack));
        if ($term instanceof PrologVariable)
            $result[] = $term;
        elseif ($term instanceof Compound)
            array_push($stack, ...array_reverse($term->args));
    }
    return $result;
}

function sameKind(mixed $a, mixed $b): bool
{
    $a = dereference($a);
    $b = dereference($b);
    if ($a instanceof PrologVariable || $b instanceof PrologVariable)
        return true;
    if ($a instanceof Compound && $b instanceof Compound)
        return $a->name === $b->name && count($a->args) === count($b->args);
    return $a === $b;
}

function typeError(string $kind, mixed $term): Compound
{
    return new Compound('type_error', $kind, $term);
}

function domainError(string $kind, mixed $term): Compound
{
    return new Compound('domain_error', $kind, $term);
}
