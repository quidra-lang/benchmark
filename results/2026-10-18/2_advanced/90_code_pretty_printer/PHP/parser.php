<?php

const PRECEDENCE = [
    '||' => 1,
    '&&' => 2,
    '==' => 3,
    '!=' => 3,
    '<' => 4,
    '<=' => 4,
    '>' => 4,
    '>=' => 4,
    '+' => 5,
    '-' => 5,
    '*' => 6,
    '/' => 6,
    '%' => 6,
];

function syntaxNode(string $tag, SourceToken $first, array $props = []): object
{
    return (object) (['tag' => $tag, 'first' => $first] + $props);
}

final class SourceParser
{
    private int $cursor = 0;

    public function __construct(
        private array $tokens,
    ) {}

    private function peek(): SourceToken
    {
        return $this->tokens[$this->cursor];
    }

    private function at(string $s): bool
    {
        return $this->peek()->text === $s;
    }

    private function fail(string $expected): never
    {
        $t = $this->peek();
        $actual = $t->kind === 'end' ? 'end of file' : "'{$t->text}'";
        throw new SourceError($t->line, $t->column, "expected $expected, found $actual");
    }

    private function take(string $s): SourceToken
    {
        if (!$this->at($s))
            $this->fail("'$s'");
        return $this->tokens[$this->cursor++];
    }

    private function identifier(): SourceToken
    {
        if ($this->peek()->kind !== 'identifier')
            $this->fail('identifier');
        return $this->tokens[$this->cursor++];
    }

    private function type(): SourceToken
    {
        if (!$this->isType())
            $this->fail('type');
        return $this->tokens[$this->cursor++];
    }

    private function isType(): bool
    {
        return in_array($this->peek()->text, TYPES, true);
    }

    public function parse(): array
    {
        $r = [];
        while ($this->peek()->kind !== 'end')
            $r[] = $this->item();
        return $r;
    }

    private function item(): object
    {
        $typ = $this->type();
        $typ->allowed = true;
        $name = $this->identifier();
        if ($this->at('(')) {
            $parameters = $this->listOf('(', ')', $this->parameter(...), false);
            $body = $this->block();
            return syntaxNode('function', $typ, compact('typ', 'name', 'parameters', 'body'));
        }
        return $this->variable($typ, $name, true);
    }

    private function parameter(): object
    {
        $typ = $this->type();
        $name = $this->identifier();
        $brackets = [];
        while ($this->at('['))
            $brackets[] = [$this->take('['), $this->take(']')];
        return syntaxNode('parameter', $typ, compact('typ', 'name', 'brackets'));
    }

    private function variable(SourceToken $typ, SourceToken $name, bool $semicolon): object
    {
        $dimensions = [];
        while ($this->at('[')) {
            $left = $this->take('[');
            $expr = $this->at(']') ? null : $this->expression();
            $right = $this->take(']');
            $dimensions[] = [$left, $expr, $right];
        }
        $equals = $this->at('=') ? $this->take('=') : null;
        $initializer = $equals === null ? null : $this->initializer();
        $semi = $semicolon ? $this->take(';') : null;
        return syntaxNode(
            'variable',
            $typ,
            compact('typ', 'name', 'dimensions', 'equals', 'initializer', 'semi'),
        );
    }

    private function initializer(): object
    {
        return $this->at('{') ? $this->listOf('{', '}', $this->initializer(...), true) : $this->expression();
    }

    private function listOf(string $opening, string $closing, callable $element, bool $allowTrailing): object
    {
        $left = $this->take($opening);
        $elements = $commas = [];
        $trailing = null;
        if (!$this->at($closing)) {
            $x = $element();
            $x->first->allowed = true;
            $elements[] = $x;
            while ($this->at(',')) {
                $c = $this->take(',');
                if ($allowTrailing && $this->at($closing)) {
                    $c->trailingComma = true;
                    $trailing = $c;
                    break;
                }
                $commas[] = $c;
                $x = $element();
                $x->first->allowed = true;
                $elements[] = $x;
            }
        }
        $right = $this->take($closing);
        return syntaxNode(
            'list',
            $left,
            compact('left', 'right', 'elements', 'commas', 'trailing') + ['role' => $opening],
        );
    }

    private function block(): object
    {
        $left = $this->take('{');
        $statements = [];
        while (!$this->at('}') && $this->peek()->kind !== 'end') {
            $s = $this->statement();
            $s->first->allowed = true;
            $statements[] = $s;
        }
        $right = $this->take('}');
        $right->allowed = true;
        return syntaxNode('block', $left, compact('left', 'right', 'statements'));
    }

    private function statement(): object
    {
        if ($this->at('{'))
            return $this->block();
        if ($this->isType()) {
            $typ = $this->type();
            return $this->variable($typ, $this->identifier(), true);
        }
        if ($this->at('if'))
            return $this->ifStatement();
        if ($this->at('while')) {
            $keyword = $this->take('while');
            $left = $this->take('(');
            $test = $this->expression();
            $right = $this->take(')');
            $body = $this->body();
            return syntaxNode('while', $keyword, compact('keyword', 'left', 'test', 'right', 'body'));
        }
        if ($this->at('for'))
            return $this->forStatement();
        if ($this->at('switch'))
            return $this->switchStatement();
        if ($this->at('return')) {
            $keyword = $this->take('return');
            $expr = $this->at(';') ? null : $this->expression();
            $semi = $this->take(';');
            return syntaxNode('return', $keyword, compact('keyword', 'expr', 'semi'));
        }
        if ($this->at('break') || $this->at('continue')) {
            $keyword = $this->tokens[$this->cursor++];
            $semi = $this->take(';');
            return syntaxNode('flow', $keyword, compact('keyword', 'semi'));
        }
        $value = $this->simple();
        $semi = $this->take(';');
        return syntaxNode('simple_stmt', $value->first, compact('value', 'semi'));
    }

    private function body(): object
    {
        $s = $this->statement();
        if ($s->tag !== 'block')
            $s->first->allowed = true;
        return $s;
    }

    private function ifStatement(): object
    {
        $keyword = $this->take('if');
        $left = $this->take('(');
        $test = $this->expression();
        $right = $this->take(')');
        $body = $this->body();
        $elseToken = $this->at('else') ? $this->take('else') : null;
        $alternative = null;
        if ($elseToken !== null) {
            if ($this->at('if'))
                $alternative = $this->ifStatement();
            else
                $alternative = $this->body();
        }
        return syntaxNode(
            'if',
            $keyword,
            compact('keyword', 'left', 'test', 'right', 'body', 'elseToken', 'alternative'),
        );
    }

    private function forStatement(): object
    {
        $keyword = $this->take('for');
        $left = $this->take('(');
        if ($this->at(';'))
            $initial = null;
        elseif ($this->isType()) {
            $typ = $this->type();
            $initial = $this->variable($typ, $this->identifier(), false);
        } else
            $initial = $this->simple();
        $firstSemi = $this->take(';');
        $condition = $this->at(';') ? null : $this->expression();
        $secondSemi = $this->take(';');
        $update = $this->at(')') ? null : $this->simple();
        $right = $this->take(')');
        $body = $this->body();
        return syntaxNode(
            'for',
            $keyword,
            compact(
                'keyword',
                'left',
                'initial',
                'firstSemi',
                'condition',
                'secondSemi',
                'update',
                'right',
                'body',
            ),
        );
    }

    private function switchStatement(): object
    {
        $keyword = $this->take('switch');
        $left = $this->take('(');
        $test = $this->expression();
        $right = $this->take(')');
        $opening = $this->take('{');
        $clauses = [];
        while ($this->at('case') || $this->at('default')) {
            $label = $this->tokens[$this->cursor++];
            $label->allowed = true;
            $value = $label->text === 'case' ? $this->expression() : null;
            $colon = $this->take(':');
            $statements = [];
            while (
                !in_array($this->peek()->text, ['case', 'default', '}'], true)
                && $this->peek()->kind !== 'end'
            ) {
                $s = $this->statement();
                $s->first->allowed = true;
                $statements[] = $s;
            }
            $clauses[] = syntaxNode('clause', $label, compact('label', 'value', 'colon', 'statements'));
        }
        $closing = $this->take('}');
        $closing->allowed = true;
        return syntaxNode(
            'switch',
            $keyword,
            compact('keyword', 'left', 'test', 'right', 'opening', 'closing', 'clauses'),
        );
    }

    private function simple(): object
    {
        $left = $this->expression();
        if (in_array($this->peek()->text, ASSIGNMENTS, true)) {
            $op = $this->tokens[$this->cursor++];
            $right = $this->expression();
            return syntaxNode('assign', $left->first, compact('left', 'op', 'right'));
        }
        return syntaxNode('expr_stmt', $left->first, ['expr' => $left]);
    }

    private function expression(): object
    {
        $test = $this->binary(1);
        if (!$this->at('?'))
            return $test;
        $question = $this->take('?');
        $yes = $this->expression();
        $colon = $this->take(':');
        $no = $this->expression();
        return syntaxNode(
            'conditional',
            $test->first,
            compact('test', 'question', 'yes', 'colon', 'no') + ['level' => 0],
        );
    }

    private function binary(int $p): object
    {
        if ($p > 6)
            return $this->unary();
        $left = $this->binary($p + 1);
        while ((PRECEDENCE[$this->peek()->text] ?? 0) === $p) {
            $op = $this->tokens[$this->cursor++];
            $right = $this->binary($p + 1);
            $left = syntaxNode('binary', $left->first, compact('left', 'op', 'right') + ['level' => $p]);
        }
        return $left;
    }

    private function unary(): object
    {
        if ($this->at('-') || $this->at('!')) {
            $op = $this->tokens[$this->cursor++];
            return syntaxNode('unary', $op, ['op' => $op, 'operand' => $this->unary(), 'level' => 7]);
        }
        $target = $this->primary();
        while (true) {
            if ($this->at('('))
                $target = syntaxNode('call', $target->first, [
                    'target' => $target,
                    'arguments' => $this->listOf('(', ')', $this->expression(...), false),
                    'level' => 8,
                ]);
            elseif ($this->at('[')) {
                $left = $this->take('[');
                $index = $this->expression();
                $right = $this->take(']');
                $target = syntaxNode(
                    'index',
                    $target->first,
                    compact('target', 'left', 'index', 'right') + ['level' => 8],
                );
            } elseif ($this->at('.')) {
                $dot = $this->take('.');
                $member = $this->identifier();
                $target = syntaxNode(
                    'member',
                    $target->first,
                    compact('target', 'dot', 'member') + ['level' => 8],
                );
            } else
                return $target;
        }
    }

    private function primary(): object
    {
        $t = $this->peek();
        if (
            in_array($t->kind, ['identifier', 'number', 'string'], true)
            || in_array($t->text, ['true', 'false'], true)
        ) {
            ++$this->cursor;
            return syntaxNode('primary', $t, ['value' => $t, 'level' => 8]);
        }
        if ($this->at('(')) {
            $left = $this->take('(');
            $inner = $this->expression();
            $right = $this->take(')');
            return syntaxNode('paren', $left, compact('left', 'inner', 'right') + ['level' => 8]);
        }
        $this->fail('expression');
    }
}
