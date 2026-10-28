<?php

function canComplete(object $n): bool
{
    if (isset($n->completes))
        return $n->completes;
    return $n->completes = match ($n->kind) {
        'return', 'break', 'continue' => false,
        'block' => array_all($n->statements, canComplete(...)),
        'if' => $n->otherwise === null || canComplete($n->then) || canComplete($n->otherwise),
        default => true,
    };
}

final class Analyzer
{
    public array $globals = [], $functions = [], $variables = [];
    private array $scopes = [];
    private ?object $function = null;

    public function __construct(
        private array $declarations,
        private array $endPosition,
    ) {}

    private function fail(array $p, string $message): never
    {
        throw new ToyCompileError('semantic', $p, $message);
    }

    private function prepare(object $n): void
    {
        $n->references = [];
        $n->readAccesses = 0;
        if ($n->kind === 'function') {
            $n->calls = [];
            $this->functions[] = $n;
        } else
            $this->variables[] = $n;
    }

    private function lookup(string $name, array $p, bool $read = true): ?object
    {
        $r = null;
        for ($i = count($this->scopes) - 1; $i >= 0; --$i)
            if (isset($this->scopes[$i][$name])) {
                $r = $this->scopes[$i][$name];
                break;
            }
        $r ??= $this->globals[$name] ?? null;
        if ($r !== null) {
            $r->references[] = $p;
            if ($read)
                ++$r->readAccesses;
        }
        return $r;
    }

    private function variable(string $name, array $p, bool $indexed, bool $read = true): object
    {
        $r = $this->lookup($name, $p, $read);
        if ($r === null)
            $this->fail($p, "undeclared identifier '$name'");
        if ($r->kind === 'function')
            $this->fail($p, "'$name' is a function, not a variable");
        $array = $r->kind === 'global' && $r->size !== null;
        if ($indexed && !$array)
            $this->fail($p, "'$name' is not an array");
        if (!$indexed && $array)
            $this->fail($p, "array '$name' used without index");
        return $r;
    }

    private function expression(object $n, bool $callStatement = false): string
    {
        $kind = $n->kind;
        if ($kind === 'integer' || $kind === 'read')
            $r = 'int';
        elseif ($kind === 'boolean')
            $r = 'bool';
        elseif ($kind === 'variable' || $kind === 'array') {
            $n->referent = $this->variable($n->name, $n->position, $kind === 'array');
            if ($kind === 'array' && $this->expression($n->index) !== 'int')
                $this->fail($n->position, "index of '{$n->name}' must be int");
            $r = $n->referent->type;
        } elseif ($kind === 'call') {
            $ref = $this->lookup($n->name, $n->position);
            if ($ref === null)
                $this->fail($n->position, "undeclared function '{$n->name}'");
            if ($ref->kind !== 'function')
                $this->fail($n->position, "'{$n->name}' is not a function");
            $n->referent = $ref;
            $this->function->calls[$ref->name] = $ref;
            $expected = count($ref->parameters);
            $found = count($n->arguments);
            if ($expected !== $found)
                $this->fail(
                    $n->position,
                    "wrong number of arguments to '{$n->name}' (expected $expected, found $found)",
                );
            foreach ($n->arguments as $i => $arg)
                if ($this->expression($arg) !== $ref->parameters[$i]->type)
                    $this->fail(
                        $n->position,
                        'argument ' . ($i + 1) . " of '{$n->name}' must be {$ref->parameters[$i]->type}",
                    );
            if (!$callStatement && $ref->type === 'void')
                $this->fail($n->position, "void function '{$n->name}' used as a value");
            $r = $ref->type;
        } elseif ($kind === 'unary') {
            $r = $this->expression($n->operand);
            $required = $n->operator === '-' ? 'int' : 'bool';
            if ($r !== $required)
                $this->fail($n->position, "operator '{$n->operator}' requires $required operand");
        } else {
            $a = $this->expression($n->left);
            $b = $this->expression($n->right);
            $op = $n->operator;
            if (in_array($op, ['+', '-', '*', '/', '%', '<', '<=', '>', '>='], true)) {
                if ($a !== 'int' || $b !== 'int')
                    $this->fail($n->position, "operator '$op' requires int operands");
                $r = in_array($op, ['+', '-', '*', '/', '%'], true) ? 'int' : 'bool';
            } elseif ($op === '==' || $op === '!=') {
                if ($a !== $b)
                    $this->fail($n->position, "operator '$op' requires operands of the same type");
                $r = 'bool';
            } else {
                if ($a !== 'bool' || $b !== 'bool')
                    $this->fail($n->position, "operator '$op' requires bool operands");
                $r = 'bool';
            }
        }
        $n->type = $r;
        return $r;
    }

    private function constantInitializer(object $n): string
    {
        $positions = [];
        $pending = [$n];
        while ($pending) {
            $x = array_pop($pending);
            if (in_array($x->kind, ['variable', 'array', 'call', 'read'], true))
                $positions[] = $x->position;
            array_push($pending, ...expressionChildren($x));
        }
        if ($positions) {
            usort($positions, fn($a, $b) => $a <=> $b);
            $this->fail($positions[0], 'global initializer must be constant');
        }
        return $this->expression($n);
    }

    private function statement(object $n, int $depth = 0): void
    {
        switch ($n->kind) {
            case 'declaration':
                if ($n->type === 'void')
                    $this->fail($n->namePosition, "variable '{$n->name}' cannot have type void");
                if (isset($this->scopes[count($this->scopes) - 1][$n->name]))
                    $this->fail($n->namePosition, "redeclaration of '{$n->name}'");
                if ($n->initializer !== null && $this->expression($n->initializer) !== $n->type)
                    $this->fail($n->namePosition, "type mismatch in initialization of '{$n->name}'");
                $this->prepare($n);
                $this->scopes[count($this->scopes) - 1][$n->name] = $n;
                break;
            case 'assignment':
                $n->referent = $this->variable($n->name, $n->position, $n->index !== null, false);
                if ($n->index !== null && $this->expression($n->index) !== 'int')
                    $this->fail($n->position, "index of '{$n->name}' must be int");
                if ($this->expression($n->value) !== $n->referent->type)
                    $this->fail($n->position, "type mismatch in assignment to '{$n->name}'");
                break;
            case 'call_statement':
                $this->expression($n->expression, true);
                break;
            case 'if':
            case 'while':
                if ($this->expression($n->condition) !== 'bool')
                    $this->fail($n->position, "condition of '{$n->kind}' must be bool");
                if ($n->kind === 'if') {
                    $this->statement($n->then, $depth);
                    if ($n->otherwise !== null)
                        $this->statement($n->otherwise, $depth);
                } else
                    $this->statement($n->body, $depth + 1);
                break;
            case 'for':
                $this->scopes[] = [];
                if ($n->initial !== null)
                    $this->statement($n->initial, $depth);
                if ($n->condition !== null && $this->expression($n->condition) !== 'bool')
                    $this->fail($n->position, "condition of 'for' must be bool");
                if ($n->update !== null)
                    $this->statement($n->update, $depth);
                $this->statement($n->body, $depth + 1);
                array_pop($this->scopes);
                break;
            case 'break':
            case 'continue':
                if ($depth === 0)
                    $this->fail($n->position, "'{$n->kind}' outside loop");
                break;
            case 'return':
                if ($this->function->type === 'void' && $n->value !== null)
                    $this->fail($n->position, "function '{$this->function->name}' must not return a value");
                if ($this->function->type !== 'void') {
                    if ($n->value === null)
                        $this->fail($n->position, "function '{$this->function->name}' must return a value");
                    if ($this->expression($n->value) !== $this->function->type)
                        $this->fail(
                            $n->position,
                            "return value of '{$this->function->name}' must be {$this->function->type}",
                        );
                }
                break;
            case 'print':
                foreach ($n->arguments as $i => $arg)
                    if ($this->expression($arg) !== 'int')
                        $this->fail($n->position, 'argument ' . ($i + 1) . " of 'print' must be int");
                break;
            case 'block':
                $this->scopes[] = [];
                foreach ($n->statements as $s)
                    $this->statement($s, $depth);
                array_pop($this->scopes);
                break;
        }
    }

    public function analyze(): self
    {
        foreach ($this->declarations as $n) {
            if ($n->kind === 'global') {
                if ($n->size !== null) {
                    if ($n->type !== 'int')
                        $this->fail($n->namePosition, "array '{$n->name}' must have element type int");
                    if ($n->size === 0)
                        $this->fail($n->sizePosition, "array '{$n->name}' must have a positive size");
                } elseif ($n->type === 'void')
                    $this->fail($n->namePosition, "variable '{$n->name}' cannot have type void");
            }
            if (isset($this->globals[$n->name]))
                $this->fail($n->namePosition, "redeclaration of '{$n->name}'");
            if ($n->kind === 'global') {
                if ($n->initializer !== null && $this->constantInitializer($n->initializer) !== $n->type)
                    $this->fail($n->namePosition, "type mismatch in initialization of '{$n->name}'");
            } else {
                $names = [];
                foreach ($n->parameters as $p) {
                    if ($p->type === 'void')
                        $this->fail($p->namePosition, "parameter '{$p->name}' cannot have type void");
                    if (isset($names[$p->name]))
                        $this->fail($p->namePosition, "redeclaration of '{$p->name}'");
                    $names[$p->name] = true;
                    $this->prepare($p);
                }
            }
            $this->prepare($n);
            $this->globals[$n->name] = $n;
        }
        $main = $this->globals['main'] ?? null;
        if ($main === null || $main->kind !== 'function')
            $this->fail($this->endPosition, 'no main function');
        if ($main->type !== 'void' || $main->parameters)
            $this->fail($main->namePosition, "main must be declared as 'void main()'");
        foreach ($this->functions as $function) {
            $this->function = $function;
            $scope = [];
            foreach ($function->parameters as $p)
                $scope[$p->name] = $p;
            $this->scopes = [$scope];
            foreach ($function->body->statements as $s)
                $this->statement($s);
            if ($function->type !== 'void' && canComplete($function->body))
                $this->fail($function->namePosition, "missing return in function '{$function->name}'");
        }
        return $this;
    }
}
