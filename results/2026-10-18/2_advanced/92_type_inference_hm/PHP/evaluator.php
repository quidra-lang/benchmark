<?php

final readonly class MLPair
{
    public function __construct(
        public mixed $first,
        public mixed $second,
    ) {}
}

final class ValueEnvironment
{
    public function __construct(
        public array $bindings,
    ) {}
}

final readonly class MLClosure
{
    public function __construct(
        public string $parameter,
        public MLNode $body,
        public ValueEnvironment $environment,
    ) {}
}

final readonly class MLBuiltin
{
    public function __construct(
        public Closure $behavior,
    ) {}
}

final class RuntimeFailure extends RuntimeException
{
    public function __construct(
        public array $position,
        string $message,
    ) {
        parent::__construct($message);
    }
}

function checkedInteger(int $value, array $position): int
{
    if ($value < -2147483648 || $value > 2147483647)
        throw new RuntimeFailure($position, 'integer overflow');
    return $value;
}

function compareValues(mixed $a, mixed $b, array $position): int
{
    if ($a instanceof MLClosure || $a instanceof MLBuiltin)
        throw new RuntimeFailure($position, 'functional value compared');
    if ($a instanceof MLPair) {
        $v = compareValues($a->first, $b->first, $position);
        return $v !== 0 ? $v : compareValues($a->second, $b->second, $position);
    }
    if (is_array($a)) {
        for ($i = 0; $i < min(count($a), count($b)); ++$i) {
            $v = compareValues($a[$i], $b[$i], $position);
            if ($v !== 0)
                return $v;
        }
        return count($a) <=> count($b);
    }
    return is_string($a) ? strcmp($a, $b) : $a <=> $b;
}

function binaryOperation(string $op, mixed $a, mixed $b, array $position): mixed
{
    if (in_array($op, ['+', '-', '*'], true))
        return checkedInteger(match ($op) {
            '+' => $a + $b,
            '-' => $a - $b,
            '*' => $a * $b,
        }, $position);
    if ($op === '/' || $op === 'mod') {
        if ($b === 0)
            throw new RuntimeFailure($position, 'division by zero');
        $quotient = intdiv($a, $b);
        return $op === '/' ? checkedInteger($quotient, $position) : $a - ($b * $quotient);
    }
    if ($op === '^')
        return $a . $b;
    if ($op === '::')
        return [$a, ...$b];
    $v = compareValues($a, $b, $position);
    return match ($op) {
        '=' => $v === 0,
        '<>' => $v !== 0,
        '<' => $v < 0,
        '>' => $v > 0,
        '<=' => $v <= 0,
        '>=' => $v >= 0,
    };
}

function matchPattern(MLNode $p, mixed $value, array &$bindings): bool
{
    if ($p->kind === 'wildcard')
        return true;
    if ($p->kind === 'name') {
        $bindings[$p->value] = $value;
        return true;
    }
    if (in_array($p->kind, ['integer', 'boolean', 'string'], true))
        return $p->value === $value;
    if ($p->kind === 'cons')
        return (
            $value !== []
            && matchPattern($p->children[0], $value[0], $bindings)
            && matchPattern($p->children[1], array_slice($value, 1), $bindings)
        );
    if ($p->kind === 'pair')
        return (
            matchPattern($p->children[0], $value->first, $bindings)
            && matchPattern($p->children[1], $value->second, $bindings)
        );
    if (count($p->children) !== count($value))
        return false;
    foreach ($p->children as $i => $child)
        if (!matchPattern($child, $value[$i], $bindings))
            return false;
    return true;
}

final class Evaluator
{
    public int $calls = 0;

    public function expression(MLNode $e, ValueEnvironment $env): mixed
    {
        $c = $e->children;
        switch ($e->kind) {
            case 'integer':
            case 'boolean':
            case 'string':
                return $e->value;
            case 'name':
                return $env->bindings[$e->value];
            case 'fun':
                return new MLClosure($e->value->spelling, $c[0], new ValueEnvironment($env->bindings));
            case 'apply':
                $function = $this->expression($c[0], $env);
                $arg = $this->expression($c[1], $env);
                ++$this->calls;
                if ($function instanceof MLBuiltin)
                    return ($function->behavior)($arg, $e->position);
                $inner = new ValueEnvironment($function->environment->bindings);
                if ($function->parameter !== '_')
                    $inner->bindings[$function->parameter] = $arg;
                return $this->expression($function->body, $inner);
            case 'binary':
                $a = $this->expression($c[0], $env);
                $op = $e->value->spelling;
                if ($op === '&&')
                    return $a ? $this->expression($c[1], $env) : false;
                if ($op === '||')
                    return $a ? true : $this->expression($c[1], $env);
                $b = $this->expression($c[1], $env);
                return binaryOperation($op, $a, $b, $e->value->position);
            case 'negate':
                return checkedInteger(-$this->expression($c[0], $env), $e->value->position);
            case 'if':
                return $this->expression($this->expression($c[0], $env) ? $c[1] : $c[2], $env);
            case 'pair':
                $a = $this->expression($c[0], $env);
                $b = $this->expression($c[1], $env);
                return new MLPair($a, $b);
            case 'list':
                $values = [];
                foreach ($c as $child)
                    $values[] = $this->expression($child, $env);
                return $values;
            case 'match':
                $value = $this->expression($c[0], $env);
                foreach ($e->value as [$p, $arm]) {
                    $bindings = [];
                    if (matchPattern($p, $value, $bindings))
                        return $this->expression(
                            $arm,
                            new ValueEnvironment(array_replace($env->bindings, $bindings)),
                        );
                }
                throw new RuntimeFailure($e->position, 'match failure');
            case 'let':
                return $this->expression($c[0], $this->group($e->value, $env));
        }
    }

    public function group(BindingGroup $g, ValueEnvironment $env): ValueEnvironment
    {
        $result = new ValueEnvironment($env->bindings);
        if ($g->recPosition !== null)
            foreach ($g->bindings as $b) {
                $e = $b->expression;
                $result->bindings[$b->name] = new MLClosure($e->value->spelling, $e->children[0], $result);
            }
        else {
            $values = [];
            foreach ($g->bindings as $b)
                $values[] = $this->expression($b->expression, $env);
            foreach ($g->bindings as $i => $b)
                $result->bindings[$b->name] = $values[$i];
        }
        return $result;
    }
}
