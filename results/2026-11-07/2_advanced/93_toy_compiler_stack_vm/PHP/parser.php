<?php

const TYPES = ['int', 'bool', 'void'];

const OPERATORS = [['||'], ['&&'], ['==', '!='], ['<', '<=', '>', '>='], ['+', '-'], ['*', '/', '%']];

function node(string $kind, array $position, array $fields = []): object
{
    return (object) (['kind' => $kind, 'position' => $position] + $fields);
}

function expressionChildren(object $n): array
{
    return match ($n->kind) {
        'binary' => [$n->left, $n->right],
        'unary' => [$n->operand],
        'array' => [$n->index],
        'call' => $n->arguments,
        default => [],
    };
}

function statementChildren(object $n): array
{
    return match ($n->kind) {
        'block' => $n->statements,
        'if' => $n->otherwise === null ? [$n->then] : [$n->then, $n->otherwise],
        'while' => [$n->body],
        'for' => array_values(array_filter([$n->initial, $n->update, $n->body], fn($v) => $v !== null)),
        default => [],
    };
}

final class ToyParser
{
    private int $index = 0;

    public function __construct(
        private array $tokens,
    ) {}

    private function peek(): Token
    {
        return $this->tokens[$this->index];
    }

    private function fail(): never
    {
        $t = $this->peek();
        throw new ToyCompileError(
            'syntax',
            $t->position,
            $t->kind === 'end' ? 'unexpected end of program' : "unexpected '{$t->spelling}'",
        );
    }

    private function take(): Token
    {
        return $this->tokens[$this->index++];
    }

    private function accept(string $s): ?Token
    {
        return $this->peek()->spelling === $s ? $this->take() : null;
    }

    private function expect(string $s): Token
    {
        if ($this->peek()->spelling !== $s)
            $this->fail();
        return $this->take();
    }

    private function identifier(): Token
    {
        if ($this->peek()->kind !== 'identifier')
            $this->fail();
        return $this->take();
    }

    private function head(): array
    {
        if (!in_array($this->peek()->spelling, TYPES, true))
            $this->fail();
        $type = $this->take();
        $name = $this->identifier();
        return [
            $type->position,
            ['type' => $type->spelling, 'name' => $name->spelling, 'namePosition' => $name->position],
        ];
    }

    public function parse(): array
    {
        $decls = [];
        while ($this->peek()->kind !== 'end') {
            [$position, $fields] = $this->head();
            if ($this->accept('(') !== null) {
                $parameters = [];
                if ($this->peek()->spelling !== ')') {
                    do {
                        [$pp, $pf] = $this->head();
                        $parameters[] = node('parameter', $pp, $pf);
                    } while ($this->accept(',') !== null);
                }
                $this->expect(')');
                $body = $this->block();
                $decls[] = node('function', $position, $fields + compact('parameters', 'body'));
            } else {
                $size = $sizePosition = $initializer = null;
                if ($this->accept('[') !== null) {
                    if ($this->peek()->kind !== 'integer')
                        $this->fail();
                    $t = $this->take();
                    $size = (int) $t->spelling;
                    $sizePosition = $t->position;
                    $this->expect(']');
                } elseif ($this->accept('=') !== null)
                    $initializer = $this->expression();
                $this->expect(';');
                $decls[] = node(
                    'global',
                    $position,
                    $fields + compact('size', 'sizePosition', 'initializer'),
                );
            }
        }
        return $decls;
    }

    private function declaration(bool $initial = false): object
    {
        [$p, $fields] = $this->head();
        $initializer = null;
        if ($initial) {
            $this->expect('=');
            $initializer = $this->expression();
        } else {
            if ($this->accept('=') !== null)
                $initializer = $this->expression();
            $this->expect(';');
        }
        return node('declaration', $p, $fields + compact('initializer'));
    }

    private function block(): object
    {
        $left = $this->expect('{');
        $statements = [];
        while ($this->peek()->spelling !== '}')
            $statements[] = in_array($this->peek()->spelling, TYPES, true)
                ? $this->declaration()
                : $this->statement();
        $right = $this->expect('}');
        return node('block', $left->position, [
            'statements' => $statements,
            'endPosition' => $right->position,
        ]);
    }

    private function statement(): object
    {
        $t = $this->peek();
        $s = $t->spelling;
        if ($s === '{')
            return $this->block();
        if ($s === 'if' || $s === 'while') {
            $this->take();
            $this->expect('(');
            $condition = $this->expression();
            $this->expect(')');
            $body = $this->statement();
            if ($s === 'while')
                return node('while', $t->position, compact('condition', 'body'));
            $otherwise = $this->accept('else') === null ? null : $this->statement();
            return node('if', $t->position, [
                'condition' => $condition,
                'then' => $body,
                'otherwise' => $otherwise,
            ]);
        }
        if ($s === 'for') {
            $this->take();
            $this->expect('(');
            $initial = null;
            if (in_array($this->peek()->spelling, TYPES, true))
                $initial = $this->declaration(true);
            elseif ($this->peek()->spelling !== ';')
                $initial = $this->simple();
            $this->expect(';');
            $condition = $this->peek()->spelling === ';' ? null : $this->expression();
            $this->expect(';');
            $update = $this->peek()->spelling === ')' ? null : $this->simple();
            $this->expect(')');
            $body = $this->statement();
            return node('for', $t->position, compact('initial', 'condition', 'update', 'body'));
        }
        if ($s === 'break' || $s === 'continue') {
            $this->take();
            $this->expect(';');
            return node($s, $t->position);
        }
        if ($s === 'return') {
            $this->take();
            $value = $this->peek()->spelling === ';' ? null : $this->expression();
            $this->expect(';');
            return node('return', $t->position, compact('value'));
        }
        if ($s === 'print') {
            $this->take();
            $this->expect('(');
            $arguments = [$this->expression()];
            while ($this->accept(',') !== null)
                $arguments[] = $this->expression();
            $this->expect(')');
            $this->expect(';');
            return node('print', $t->position, compact('arguments'));
        }
        if ($t->kind === 'identifier' || $s === 'read') {
            $result = $this->simple();
            $this->expect(';');
            return $result;
        }
        $this->fail();
    }

    private function simple(): object
    {
        $t = $this->peek();
        if ($t->kind !== 'identifier' && $t->spelling !== 'read')
            $this->fail();
        $value = $this->primary();
        if ($value->kind === 'call' || $value->kind === 'read')
            return node('call_statement', $value->position, ['expression' => $value]);
        $this->expect('=');
        return node('assignment', $value->position, [
            'name' => $value->name,
            'index' => $value->kind === 'array' ? $value->index : null,
            'value' => $this->expression(),
        ]);
    }

    private function expression(int $level = 0): object
    {
        if ($level === count(OPERATORS)) {
            if (in_array($this->peek()->spelling, ['-', '!'], true)) {
                $op = $this->take();
                return node('unary', $op->position, [
                    'operator' => $op->spelling,
                    'operand' => $this->expression($level),
                ]);
            }
            return $this->primary();
        }
        $r = $this->expression($level + 1);
        while (in_array($this->peek()->spelling, OPERATORS[$level], true)) {
            $op = $this->take();
            $r = node('binary', $op->position, [
                'operator' => $op->spelling,
                'left' => $r,
                'right' => $this->expression($level + 1),
            ]);
        }
        return $r;
    }

    private function primary(): object
    {
        $t = $this->peek();
        if ($t->kind === 'integer') {
            $this->take();
            return node('integer', $t->position, ['value' => (int) $t->spelling]);
        }
        if ($t->spelling === 'true' || $t->spelling === 'false') {
            $this->take();
            return node('boolean', $t->position, ['value' => $t->spelling === 'true']);
        }
        if ($t->spelling === 'read') {
            $this->take();
            $this->expect('(');
            $this->expect(')');
            return node('read', $t->position);
        }
        if ($this->accept('(') !== null) {
            $r = $this->expression();
            $this->expect(')');
            return $r;
        }
        if ($t->kind === 'identifier') {
            $this->take();
            if ($this->accept('(') !== null) {
                $arguments = [];
                if ($this->peek()->spelling !== ')') {
                    $arguments[] = $this->expression();
                    while ($this->accept(',') !== null)
                        $arguments[] = $this->expression();
                }
                $this->expect(')');
                return node('call', $t->position, ['name' => $t->spelling, 'arguments' => $arguments]);
            }
            if ($this->accept('[') !== null) {
                $index = $this->expression();
                $this->expect(']');
                return node('array', $t->position, ['name' => $t->spelling, 'index' => $index]);
            }
            return node('variable', $t->position, ['name' => $t->spelling]);
        }
        $this->fail();
    }
}
