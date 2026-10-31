<?php

final class InferenceError extends RuntimeException
{
    public function __construct(
        public string $kind,
        public array $position,
        public array $details,
    ) {
        parent::__construct();
    }
}

function operatorTypes(string $op): array
{
    if (in_array($op, ['+', '-', '*', '/', 'mod'], true))
        return [new MLType('int'), new MLType('int'), new MLType('int')];
    if ($op === '^')
        return [new MLType('string'), new MLType('string'), new MLType('string')];
    if ($op === '&&' || $op === '||')
        return [new MLType('bool'), new MLType('bool'), new MLType('bool')];
    $v = new TypeVariable();
    if ($op === '::') {
        $list = new MLType('list', $v);
        return [$v, $list, $list];
    }
    return [$v, $v, new MLType('bool')];
}

final class Inferencer
{
    public array $localBindings = [];

    private function check(TypeVariable|MLType $expected, TypeVariable|MLType $found, array $position): void
    {
        try {
            unify($expected, $found);
        } catch (UnificationFailure $failure) {
            throw new InferenceError('check', $position, compact('expected', 'found', 'failure'));
        }
    }

    public function expression(MLNode $e, array $env): TypeVariable|MLType
    {
        $c = $e->children;
        switch ($e->kind) {
            case 'integer':
            case 'boolean':
            case 'string':
                $r = new MLType(['integer' => 'int', 'boolean' => 'bool', 'string' => 'string'][$e->kind]);
                break;
            case 'name':
                if (!isset($env[$e->value]))
                    throw new InferenceError('unbound', $e->position, [
                        'name' => $e->value,
                        'candidates' => array_keys($env),
                    ]);
                $r = instantiate($env[$e->value]);
                break;
            case 'fun':
                $arg = new TypeVariable();
                $inner = $env;
                if ($e->value->spelling !== '_')
                    $inner[$e->value->spelling] = new TypeScheme($arg);
                $r = new MLType('function', $arg, $this->expression($c[0], $inner));
                break;
            case 'apply':
                $function = resolve($this->expression($c[0], $env));
                if ($function instanceof TypeVariable) {
                    $arg = new TypeVariable();
                    $r = new TypeVariable();
                    $function->binding = new MLType('function', $arg, $r);
                } elseif ($function->kind === 'function')
                    [$arg, $r] = $function->children;
                else
                    throw new InferenceError('not_function', $c[0]->position, ['found' => $function]);
                $this->check($arg, $this->expression($c[1], $env), $c[1]->position);
                break;
            case 'binary':
                [$first, $second, $r] = operatorTypes($e->value->spelling);
                $this->check($first, $this->expression($c[0], $env), $c[0]->position);
                $this->check($second, $this->expression($c[1], $env), $c[1]->position);
                break;
            case 'negate':
                $this->check(new MLType('int'), $this->expression($c[0], $env), $c[0]->position);
                $r = new MLType('int');
                break;
            case 'if':
                $this->check(new MLType('bool'), $this->expression($c[0], $env), $c[0]->position);
                $r = $this->expression($c[1], $env);
                $found = $this->expression($c[2], $env);
                $this->check($r, $found, $c[2]->position);
                break;
            case 'pair':
                $a = $this->expression($c[0], $env);
                $b = $this->expression($c[1], $env);
                $r = new MLType('pair', $a, $b);
                break;
            case 'list':
                $element = new TypeVariable();
                foreach ($c as $x)
                    $this->check($element, $this->expression($x, $env), $x->position);
                $r = new MLType('list', $element);
                break;
            case 'match':
                $matched = $this->expression($c[0], $env);
                $r = new TypeVariable();
                foreach ($e->value as [$pattern, $arm]) {
                    $bindings = [];
                    $pt = $this->pattern($pattern, $bindings);
                    $this->check($matched, $pt, $pattern->position);
                    $inner = $env;
                    foreach ($bindings as $name => $type)
                        $inner[$name] = new TypeScheme($type);
                    $this->check($r, $this->expression($arm, $inner), $arm->position);
                }
                break;
            case 'let':
                $inner = $this->group($e->value, $env, true);
                $r = $this->expression($c[0], $inner);
                break;
        }
        $e->inferred = $r;
        return $r;
    }

    private function pattern(MLNode $p, array &$bindings): TypeVariable|MLType
    {
        $c = $p->children;
        if ($p->kind === 'wildcard')
            return new TypeVariable();
        if ($p->kind === 'name') {
            if (isset($bindings[$p->value]))
                throw new InferenceError('duplicate_pattern', $p->position, ['name' => $p->value]);
            return $bindings[$p->value] = new TypeVariable();
        }
        if (in_array($p->kind, ['integer', 'boolean', 'string'], true))
            return new MLType(['integer' => 'int', 'boolean' => 'bool', 'string' => 'string'][$p->kind]);
        if ($p->kind === 'pair') {
            $a = $this->pattern($c[0], $bindings);
            $b = $this->pattern($c[1], $bindings);
            return new MLType('pair', $a, $b);
        }
        $element = new TypeVariable();
        $sequence = new MLType('list', $element);
        if ($p->kind === 'cons') {
            $this->check($element, $this->pattern($c[0], $bindings), $c[0]->position);
            $this->check($sequence, $this->pattern($c[1], $bindings), $c[1]->position);
        } else
            foreach ($c as $x)
                $this->check($element, $this->pattern($x, $bindings), $x->position);
        return $sequence;
    }

    public function group(BindingGroup $group, array $env, bool $local = false): array
    {
        $names = [];
        foreach ($group->bindings as $b) {
            if (isset($names[$b->name]))
                throw new InferenceError('duplicate_let', $b->position, ['name' => $b->name]);
            $names[$b->name] = true;
            if ($group->recPosition !== null && $b->expression->kind !== 'fun')
                throw new InferenceError('recursive_function', $b->position, ['name' => $b->name]);
        }
        $types = [];
        if ($group->recPosition === null)
            foreach ($group->bindings as $b)
                $types[] = $this->expression($b->expression, $env);
        else {
            $recursive = $env;
            foreach ($group->bindings as $b) {
                $v = new TypeVariable();
                $types[] = $v;
                $recursive[$b->name] = new TypeScheme($v);
            }
            foreach ($group->bindings as $i => $b)
                $this->check($types[$i], $this->expression($b->expression, $recursive), $b->position);
        }
        $r = $env;
        foreach ($group->bindings as $i => $b) {
            $b->scheme = generalize($types[$i], $env);
            $r[$b->name] = $b->scheme;
        }
        if ($local)
            array_push($this->localBindings, ...$group->bindings);
        return $r;
    }
}
