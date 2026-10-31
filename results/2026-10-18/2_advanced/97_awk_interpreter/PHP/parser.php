<?php

const ASSIGNMENTS = ['=', '+=', '-=', '*=', '/=', '%=', '^='];

const COMPARISONS = ['<', '<=', '==', '!=', '>=', '>'];

const LVALUE_KINDS = ['name', 'array', 'field'];

const STATEMENTS = [
    'if',
    'while',
    'do',
    'for',
    'for_in',
    'print',
    'printf',
    'delete',
    'next',
    'break',
    'continue',
    'exit',
    'return',
    'expression_statement',
];

function node(string $kind, array $position, array $children = [], array $fields = []): object
{
    return (object) (
        [
            'kind' => $kind,
            'position' => $position,
            'children' => array_values(array_filter($children, fn($c) => $c !== null)),
        ] + $fields
    );
}

final class AwkParser
{
    private int $index = 0, $loopDepth = 0;
    private bool $function = false;
    private ?string $phase = null;

    public function __construct(
        private array $tokens,
    ) {}

    private function peek(): Token
    {
        return $this->tokens[$this->index];
    }

    private function take(): Token
    {
        return $this->tokens[$this->index++];
    }

    private function fail(?array $p = null): never
    {
        throw new SyntaxIssue($p ?? $this->peek()->position);
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

    private function name(): object
    {
        if ($this->peek()->kind !== 'name')
            $this->fail();
        $t = $this->take();
        return node('name', $t->position, fields: ['name' => $t->spelling]);
    }

    private function newlines(): void
    {
        while ($this->accept("\n") !== null) {
        }
    }

    public function parse(): array
    {
        $items = [];
        while ($this->peek()->kind !== 'end') {
            if (in_array($this->peek()->spelling, ["\n", ';'], true)) {
                $this->take();
                continue;
            }
            $start = $this->peek();
            if ($this->accept('function') !== null) {
                if (!in_array($this->peek()->kind, ['name', 'function_name'], true))
                    $this->fail();
                $name = $this->take();
                $this->expect('(');
                $parameters = [];
                if ($this->peek()->spelling !== ')') {
                    do {
                        $p = $this->name();
                        $p->kind = 'parameter';
                        $parameters[] = $p;
                        if ($this->accept(',') === null)
                            break;
                        $this->newlines();
                    } while (true);
                }
                $this->expect(')');
                $this->newlines();
                $this->function = true;
                $body = $this->block();
                $this->function = false;
                $items[] = node(
                    'function',
                    $start->position,
                    [...$parameters, $body],
                    [
                        'name' => $name->spelling,
                        'namePosition' => $name->position,
                        'parameters' => $parameters,
                        'body' => $body,
                    ],
                );
                continue;
            }
            $patterns = [];
            if ($start->spelling === 'BEGIN' || $start->spelling === 'END')
                $flavor = $this->take()->spelling;
            elseif ($start->spelling === '{')
                $flavor = 'all';
            else {
                $patterns[] = $this->expression();
                if ($this->accept(',') !== null) {
                    $this->newlines();
                    $patterns[] = $this->expression();
                }
                $flavor = count($patterns) === 2 ? 'range' : 'pattern';
            }
            $this->phase = $flavor;
            if (in_array($flavor, ['BEGIN', 'END', 'all'], true) || $this->peek()->spelling === '{')
                $action = $this->block();
            else {
                if (!in_array($this->peek()->spelling, ["\n", ';'], true) && $this->peek()->kind !== 'end')
                    $this->fail();
                $action = null;
            }
            $this->phase = null;
            $items[] = node(
                'rule',
                $start->position,
                [...$patterns, $action],
                compact('flavor', 'patterns', 'action'),
            );
        }
        return $items;
    }

    private function block(): object
    {
        $open = $this->expect('{');
        $statements = [];
        while ($this->peek()->spelling !== '}') {
            if (in_array($this->peek()->spelling, ["\n", ';'], true))
                $this->take();
            else
                $statements[] = $this->statement();
        }
        $this->expect('}');
        return node('block', $open->position, $statements, compact('statements'));
    }

    private function condition(): object
    {
        $this->expect('(');
        $v = $this->expression();
        $this->expect(')');
        return $v;
    }

    private function loopBody(): object
    {
        $this->newlines();
        ++$this->loopDepth;
        $body = $this->statement();
        --$this->loopDepth;
        return $body;
    }

    private function terminator(): void
    {
        if (in_array($this->peek()->spelling, [';', "\n"], true))
            $this->take();
        elseif ($this->peek()->spelling !== '}')
            $this->fail();
    }

    private function statement(): object
    {
        $t = $this->peek();
        $s = $t->spelling;
        if ($s === '{')
            return $this->block();
        if ($this->accept(';') !== null)
            return node('empty', $t->position);
        if ($this->accept('if') !== null) {
            $condition = $this->condition();
            $this->newlines();
            $first = $this->statement();
            $this->newlines();
            $second = null;
            if ($this->accept('else') !== null) {
                $this->newlines();
                $second = $this->statement();
            }
            return node(
                'if',
                $t->position,
                [$condition, $first, $second],
                compact('condition', 'first', 'second'),
            );
        }
        if ($this->accept('while') !== null) {
            $condition = $this->condition();
            $body = $this->loopBody();
            return node('while', $t->position, [$condition, $body], compact('condition', 'body'));
        }
        if ($this->accept('do') !== null) {
            $body = $this->loopBody();
            $this->newlines();
            $this->expect('while');
            $condition = $this->condition();
            $this->terminator();
            return node('do', $t->position, [$body, $condition], compact('body', 'condition'));
        }
        if ($this->accept('for') !== null) {
            $this->expect('(');
            $ahead = array_slice($this->tokens, $this->index, 4);
            if (
                count($ahead) === 4
                && $ahead[0]->kind === 'name'
                && $ahead[1]->spelling === 'in'
                && $ahead[2]->kind === 'name'
                && $ahead[3]->spelling === ')'
            ) {
                $variable = $this->name();
                $this->expect('in');
                $array = $this->name();
                $this->expect(')');
                $body = $this->loopBody();
                return node(
                    'for_in',
                    $t->position,
                    [$variable, $array, $body],
                    compact('variable', 'array', 'body'),
                );
            }
            $initial = $this->peek()->spelling === ';' ? null : $this->expression();
            $this->expect(';');
            $this->newlines();
            $condition = $this->peek()->spelling === ';' ? null : $this->expression();
            $this->expect(';');
            $this->newlines();
            $update = $this->peek()->spelling === ')' ? null : $this->expression();
            $this->expect(')');
            $body = $this->loopBody();
            return node(
                'for',
                $t->position,
                [$initial, $condition, $update, $body],
                compact('initial', 'condition', 'update', 'body'),
            );
        }
        if ($s === 'print' || $s === 'printf') {
            $this->take();
            $result = $this->outputStatement($t);
        } elseif ($s === 'delete') {
            $this->take();
            $array = $this->name();
            $indexes = null;
            if ($this->accept('[') !== null) {
                $indexes = $this->expressionList();
                $this->expect(']');
            }
            $result = node(
                'delete',
                $t->position,
                [$array, ...($indexes ?? [])],
                compact('array', 'indexes'),
            );
        } elseif (in_array($s, ['next', 'break', 'continue', 'exit', 'return'], true)) {
            $this->take();
            if (
                $s === 'next' && !$this->function && in_array($this->phase, ['BEGIN', 'END'], true)
                || $s === 'return' && !$this->function
                || in_array($s, ['break', 'continue'], true) && $this->loopDepth === 0
            )
                $this->fail($t->position);
            $value = null;
            if (
                in_array($s, ['exit', 'return'], true)
                && !in_array($this->peek()->spelling, [';', "\n", '}'], true)
            )
                $value = $this->expression();
            $result = node($s, $t->position, [$value], compact('value'));
        } else {
            $expression = $this->expression();
            $result = node('expression_statement', $t->position, [$expression], compact('expression'));
        }
        $this->terminator();
        return $result;
    }

    private function parenthesizedOutput(): bool
    {
        if ($this->peek()->spelling !== '(')
            return false;
        $depth = 0;
        for ($i = $this->index; $i < count($this->tokens); ++$i) {
            $s = $this->tokens[$i]->spelling;
            if ($s === '(')
                ++$depth;
            elseif ($s === ')' && --$depth === 0) {
                $next = $this->tokens[$i + 1];
                return in_array($next->spelling, [';', "\n", '}', '>', '>>'], true) || $next->kind === 'end';
            }
        }
        return false;
    }

    private function outputStatement(Token $t): object
    {
        $arguments = [];
        if ($this->parenthesizedOutput()) {
            $this->expect('(');
            $arguments = $this->expressionList();
            $this->expect(')');
        } elseif (!in_array($this->peek()->spelling, [';', "\n", '}', '>', '>>'], true))
            $arguments = $this->expressionList(false);
        if ($t->spelling === 'printf' && !$arguments)
            $this->fail();
        $redirect = in_array($this->peek()->spelling, ['>', '>>'], true) ? $this->take() : null;
        $filename = $redirect === null ? null : $this->concatenation();
        return node(
            $t->spelling,
            $t->position,
            [...$arguments, $filename],
            [
                'arguments' => $arguments,
                'redirect' => $redirect?->spelling,
                'redirectPosition' => $redirect?->position,
                'filename' => $filename,
            ],
        );
    }

    private function expressionList(bool $greater = true): array
    {
        $r = [$this->expression($greater)];
        while ($this->accept(',') !== null) {
            $this->newlines();
            $r[] = $this->expression($greater);
        }
        return $r;
    }

    private function expression(bool $greater = true): object
    {
        $left = $this->conditional($greater);
        if (
            in_array($left->kind, LVALUE_KINDS, true) && in_array($this->peek()->spelling, ASSIGNMENTS, true)
        ) {
            $op = $this->take();
            $right = $this->expression($greater);
            return node(
                'assignment',
                $op->position,
                [$left, $right],
                ['operator' => $op->spelling, 'location' => $left, 'value' => $right],
            );
        }
        return $left;
    }

    private function conditional(bool $greater): object
    {
        $condition = $this->logical(0, $greater);
        $op = $this->accept('?');
        if ($op === null)
            return $condition;
        $first = $this->conditional($greater);
        $this->expect(':');
        $second = $this->conditional($greater);
        return node(
            'conditional',
            $op->position,
            [$condition, $first, $second],
            compact('condition', 'first', 'second'),
        );
    }

    private function binary(Token $op, object $left, object $right): object
    {
        return node(
            'binary',
            $op->position,
            [$left, $right],
            ['operator' => $op->spelling, 'left' => $left, 'right' => $right],
        );
    }

    private function logical(int $level, bool $greater): object
    {
        if ($level === 2)
            return $this->membership($greater);
        $op = $level === 0 ? '||' : '&&';
        $left = $this->logical($level + 1, $greater);
        while ($this->peek()->spelling === $op) {
            $token = $this->take();
            $this->newlines();
            $left = $this->binary($token, $left, $this->logical($level + 1, $greater));
        }
        return $left;
    }

    private function membership(bool $greater): object
    {
        $left = $this->comparison($greater);
        while ($this->peek()->spelling === 'in') {
            $op = $this->take();
            $array = $this->name();
            $left = node(
                'membership',
                $op->position,
                [$left, $array],
                ['indexes' => [$left], 'array' => $array],
            );
        }
        return $left;
    }

    private function comparison(bool $greater): object
    {
        $left = $this->concatenation();
        while (
            in_array($this->peek()->spelling, COMPARISONS, true)
            && ($greater || $this->peek()->spelling !== '>')
        ) {
            $op = $this->take();
            $left = $this->binary($op, $left, $this->concatenation());
        }
        return $left;
    }

    private function concatenation(): object
    {
        $left = $this->additive();
        while (
            in_array($this->peek()->kind, ['number', 'string', 'name', 'function_name', 'builtin'], true)
            || in_array($this->peek()->spelling, ['$', '(', '++', '--'], true)
        ) {
            $p = $this->peek()->position;
            $right = $this->additive();
            $left = node(
                'binary',
                $p,
                [$left, $right],
                ['operator' => 'concat', 'left' => $left, 'right' => $right],
            );
        }
        return $left;
    }

    private function additive(): object
    {
        $left = $this->multiplicative();
        while (in_array($this->peek()->spelling, ['+', '-'], true)) {
            $op = $this->take();
            $left = $this->binary($op, $left, $this->multiplicative());
        }
        return $left;
    }

    private function multiplicative(): object
    {
        $left = $this->unary();
        while (in_array($this->peek()->spelling, ['*', '/', '%'], true)) {
            $op = $this->take();
            $left = $this->binary($op, $left, $this->unary());
        }
        return $left;
    }

    private function unary(): object
    {
        if (in_array($this->peek()->spelling, ['!', '-', '+'], true)) {
            $op = $this->take();
            $operand = $this->unary();
            return node(
                'unary',
                $op->position,
                [$operand],
                ['operator' => $op->spelling, 'operand' => $operand],
            );
        }
        $left = $this->postfix();
        if ($this->peek()->spelling === '^') {
            $op = $this->take();
            $left = $this->binary($op, $left, $this->unary());
        }
        return $left;
    }

    private function prefix(): object
    {
        $op = $this->take();
        $location = $this->lvalue();
        return node(
            'increment',
            $op->position,
            [$location],
            ['location' => $location, 'delta' => $op->spelling === '++' ? 1 : -1, 'prefix' => true],
        );
    }

    private function postfix(): object
    {
        if (in_array($this->peek()->spelling, ['++', '--'], true))
            return $this->prefix();
        $left = $this->atom();
        if (
            in_array($left->kind, LVALUE_KINDS, true) && in_array($this->peek()->spelling, ['++', '--'], true)
        ) {
            $op = $this->take();
            return node(
                'increment',
                $op->position,
                [$left],
                ['location' => $left, 'delta' => $op->spelling === '++' ? 1 : -1, 'prefix' => false],
            );
        }
        return $left;
    }

    private function lvalue(): object
    {
        if ($this->peek()->kind === 'name') {
            $n = $this->name();
            if ($this->accept('[') !== null) {
                $indexes = $this->expressionList();
                $this->expect(']');
                return node('array', $n->position, $indexes, ['name' => $n->name, 'indexes' => $indexes]);
            }
            return $n;
        }
        $dollar = $this->accept('$');
        if ($dollar !== null) {
            $index = in_array($this->peek()->spelling, ['++', '--'], true) ? $this->prefix() : $this->atom();
            return node('field', $dollar->position, [$index], compact('index'));
        }
        $this->fail();
    }

    private function atom(): object
    {
        $t = $this->peek();
        if ($t->kind === 'number' || $t->kind === 'string') {
            $this->take();
            return node($t->kind, $t->position, fields: ['value' => $t->value]);
        }
        if ($t->kind === 'name' || $t->spelling === '$')
            return $this->lvalue();
        if ($this->accept('(') !== null) {
            $expressions = $this->expressionList();
            $this->expect(')');
            if (count($expressions) === 1)
                return node('paren', $t->position, $expressions, ['expression' => $expressions[0]]);
            $this->expect('in');
            $array = $this->name();
            return node(
                'membership',
                $t->position,
                [...$expressions, $array],
                ['indexes' => $expressions, 'array' => $array],
            );
        }
        if ($t->kind === 'function_name' || $t->kind === 'builtin') {
            $this->take();
            $arguments = [];
            if ($this->accept('(') !== null) {
                if ($this->peek()->spelling !== ')')
                    $arguments = $this->expressionList();
                $this->expect(')');
            } elseif ($t->kind === 'function_name' || $t->spelling !== 'length')
                $this->fail();
            $kind = $t->kind === 'function_name' ? 'call' : 'builtin';
            if ($kind === 'builtin')
                $this->checkBuiltin($t, $arguments);
            return node($kind, $t->position, $arguments, ['name' => $t->spelling, 'arguments' => $arguments]);
        }
        if ($this->accept('getline') !== null) {
            $target =
                $this->peek()->kind === 'name' || $this->peek()->spelling === '$' ? $this->lvalue() : null;
            $filename = $this->accept('<') !== null ? $this->atom() : null;
            return node('getline', $t->position, [$target, $filename], compact('target', 'filename'));
        }
        $this->fail();
    }

    private function checkBuiltin(Token $t, array $args): void
    {
        $n = count($args);
        $valid = match ($t->spelling) {
            'length' => in_array($n, [0, 1], true),
            'substr', 'split' => in_array($n, [2, 3], true),
            'index' => $n === 2,
            'sprintf' => $n >= 1,
            default => $n === 1,
        };
        if (!$valid || $t->spelling === 'split' && $args[1]->kind !== 'name')
            $this->fail($t->position);
    }
}
