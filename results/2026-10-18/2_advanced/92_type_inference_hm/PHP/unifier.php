<?php

final class TypeVariable
{
    public TypeVariable|MLType|null $binding = null;
}

final readonly class MLType
{
    public array $children;

    public function __construct(
        public string $kind,
        TypeVariable|self ...$children,
    ) {
        $this->children = $children;
    }
}

final readonly class TypeScheme
{
    public function __construct(
        public TypeVariable|MLType $value,
        public array $quantified = [],
    ) {}
}

function resolve(TypeVariable|MLType $v): TypeVariable|MLType
{
    $path = [];
    while ($v instanceof TypeVariable && $v->binding !== null) {
        $path[] = $v;
        $v = $v->binding;
    }
    foreach ($path as $x)
        $x->binding = $v;
    return $v;
}

function occurs(TypeVariable $variable, TypeVariable|MLType $v): bool
{
    $v = resolve($v);
    if ($v instanceof TypeVariable)
        return $variable === $v;
    foreach ($v->children as $c)
        if (occurs($variable, $c))
            return true;
    return false;
}

final class UnificationFailure extends RuntimeException
{
    public function __construct(
        public TypeVariable|MLType $expected,
        public TypeVariable|MLType $found,
        public bool $infinite,
        public bool $nested,
    ) {
        parent::__construct();
    }
}

function unify(TypeVariable|MLType $expected, TypeVariable|MLType $found, bool $nested = false): void
{
    $expected = resolve($expected);
    $found = resolve($found);
    if ($expected === $found)
        return;
    if ($expected instanceof TypeVariable) {
        if (occurs($expected, $found))
            throw new UnificationFailure($expected, $found, true, $nested);
        $expected->binding = $found;
        return;
    }
    if ($found instanceof TypeVariable) {
        if (occurs($found, $expected))
            throw new UnificationFailure($expected, $found, true, $nested);
        $found->binding = $expected;
        return;
    }
    if ($expected->kind !== $found->kind)
        throw new UnificationFailure($expected, $found, false, $nested);
    foreach ($expected->children as $i => $c)
        unify($c, $found->children[$i], true);
}

function freeVariables(TypeVariable|MLType $v): array
{
    $v = resolve($v);
    if ($v instanceof TypeVariable)
        return [spl_object_id($v) => $v];
    $r = [];
    foreach ($v->children as $c)
        $r += freeVariables($c);
    return $r;
}

function generalize(TypeVariable|MLType $v, array $env): TypeScheme
{
    $free = [];
    foreach ($env as $scheme)
        $free += array_diff_key(freeVariables($scheme->value), $scheme->quantified);
    return new TypeScheme($v, array_diff_key(freeVariables($v), $free));
}

function instantiate(TypeScheme $scheme): TypeVariable|MLType
{
    $replacements = [];
    $copy = function ($v) use (&$copy, &$replacements, $scheme) {
        $v = resolve($v);
        if ($v instanceof TypeVariable) {
            $id = spl_object_id($v);
            if (!isset($scheme->quantified[$id]))
                return $v;
            return $replacements[$id] ??= new TypeVariable();
        }
        return new MLType($v->kind, ...array_map($copy, $v->children));
    };
    return $copy($scheme->value);
}
