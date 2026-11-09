<?php

const OPERATORS = [
    '||' => [1, true],
    '&&' => [2, true],
    '=' => [3, false],
    '<>' => [3, false],
    '<' => [3, false],
    '>' => [3, false],
    '<=' => [3, false],
    '>=' => [3, false],
    '::' => [4, true],
    '^' => [4, true],
    '+' => [5, false],
    '-' => [5, false],
    '*' => [6, false],
    '/' => [6, false],
    'mod' => [6, false],
];

final class MLNode
{
    public ?object $inferred = null;

    public function __construct(
        public string $kind,
        public array $position,
        public array $children = [],
        public mixed $value = null,
    ) {}
}

final class Binding
{
    public ?TypeScheme $scheme = null;
    public string $classification = '';
    public string $name;
    public array $position;

    public function __construct(
        Token $name,
        public MLNode $expression,
    ) {
        $this->name = $name->spelling;
        $this->position = $name->position;
    }
}

final readonly class BindingGroup
{
    public function __construct(
        public array $bindings,
        public ?array $recPosition,
    ) {}
}

final readonly class Item
{
    public function __construct(
        public string $kind,
        public mixed $value,
    ) {}
}

final class SyntaxFailure extends RuntimeException
{
    public function __construct(
        public Token $token,
    ) {
        parent::__construct();
    }
}

final class MLParser
{
    private int $index = 0;

    public function __construct(
        private array $tokens,
    ) {}

    public function peek(): Token
    {
        return $this->tokens[$this->index];
    }

    private function accept(string $kind): ?Token
    {
        return $this->peek()->kind === $kind ? $this->tokens[$this->index++] : null;
    }

    private function expect(string $kind): Token
    {
        return $this->accept($kind) ?? throw new SyntaxFailure($this->peek());
    }

    private function name(): Token
    {
        if (!$this->peek()->isName())
            throw new SyntaxFailure($this->peek());
        return $this->expect('identifier');
    }

    public function recover(): void
    {
        while (!in_array($this->peek()->kind, [';;', 'EOF'], true))
            ++$this->index;
        $this->accept(';;');
    }

    public function item(): Item
    {
        if ($this->accept('val') !== null) {
            $name = $this->name();
            $this->expect(':');
            $type = $this->typeExpression();
            $this->expect(';;');
            return new Item('signature', [$name, $type]);
        }
        $opening = $this->accept('let');
        if ($opening !== null) {
            $group = $this->group();
            $result = $this->accept('in') !== null
                ? new Item('expression', new MLNode('let', $opening->position, [$this->expression()], $group))
                : new Item('declaration', $group);
        } else
            $result = new Item('expression', $this->expression());
        $this->expect(';;');
        return $result;
    }

    private function group(): BindingGroup
    {
        $rec = $this->accept('rec');
        $bindings = [$this->binding()];
        while ($this->accept('and') !== null)
            $bindings[] = $this->binding();
        return new BindingGroup($bindings, $rec?->position);
    }

    private function binding(): Binding
    {
        $name = $this->name();
        $parameters = [];
        while ($this->peek()->kind === 'identifier')
            $parameters[] = $this->expect('identifier');
        $this->expect('=');
        $expr = $this->expression();
        foreach (array_reverse($parameters) as $param)
            $expr = new MLNode('fun', $param->position, [$expr], $param);
        return new Binding($name, $expr);
    }

    private function expression(): MLNode
    {
        if (($opening = $this->accept('let')) !== null) {
            $g = $this->group();
            $this->expect('in');
            return new MLNode('let', $opening->position, [$this->expression()], $g);
        }
        if (($opening = $this->accept('fun')) !== null) {
            $parameters = [$this->expect('identifier')];
            while ($this->peek()->kind === 'identifier')
                $parameters[] = $this->expect('identifier');
            $this->expect('->');
            $expr = $this->expression();
            foreach (array_reverse($parameters) as $param)
                $expr = new MLNode('fun', $param->position, [$expr], $param);
            $expr->position = $opening->position;
            return $expr;
        }
        if (($opening = $this->accept('if')) !== null) {
            $c = $this->expression();
            $this->expect('then');
            $a = $this->expression();
            $this->expect('else');
            $b = $this->expression();
            return new MLNode('if', $opening->position, [$c, $a, $b]);
        }
        if (($opening = $this->accept('match')) !== null) {
            $e = $this->expression();
            $this->expect('with');
            $this->accept('|');
            $arms = [$this->arm()];
            while ($this->accept('|') !== null)
                $arms[] = $this->arm();
            return new MLNode('match', $opening->position, [$e], $arms);
        }
        return $this->binary(1);
    }

    private function arm(): array
    {
        $p = $this->pattern();
        $this->expect('->');
        return [$p, $this->expression()];
    }

    private function binary(int $minimum): MLNode
    {
        $e = $this->unary();
        while (isset(OPERATORS[$this->peek()->kind])) {
            [$p, $right] = OPERATORS[$this->peek()->kind];
            if ($p < $minimum)
                break;
            $op = $this->tokens[$this->index++];
            $e = new MLNode('binary', $e->position, [$e, $this->binary($right ? $p : $p + 1)], $op);
        }
        return $e;
    }

    private function startsAtom(): bool
    {
        return in_array($this->peek()->kind, ['integer', 'string', 'true', 'false', '(', '['], true)
        || $this->peek()->isName();
    }

    private function unary(): MLNode
    {
        if (($op = $this->accept('-')) !== null)
            return new MLNode('negate', $op->position, [$this->unary()], $op);
        $e = $this->atom();
        while ($this->startsAtom())
            $e = new MLNode('apply', $e->position, [$e, $this->atom()]);
        return $e;
    }

    private function atom(): MLNode
    {
        $t = $this->peek();
        if (in_array($t->kind, ['integer', 'string'], true)) {
            ++$this->index;
            return new MLNode($t->kind, $t->position, value: $t->value);
        }
        if (in_array($t->kind, ['true', 'false'], true)) {
            ++$this->index;
            return new MLNode('boolean', $t->position, value: $t->kind === 'true');
        }
        if ($t->isName()) {
            ++$this->index;
            return new MLNode('name', $t->position, value: $t->spelling);
        }
        if ($this->accept('(') !== null) {
            $first = $this->expression();
            if ($this->accept(',') !== null) {
                $second = $this->expression();
                $this->expect(')');
                return new MLNode('pair', $t->position, [$first, $second]);
            }
            $this->expect(')');
            return $first;
        }
        if ($this->accept('[') !== null) {
            $elements = [];
            if ($this->accept(']') === null) {
                $elements[] = $this->expression();
                while ($this->accept(';') !== null)
                    $elements[] = $this->expression();
                $this->expect(']');
            }
            return new MLNode('list', $t->position, $elements);
        }
        throw new SyntaxFailure($t);
    }

    private function pattern(): MLNode
    {
        $first = $this->patternAtom();
        return (
            $this->accept('::') === null
                ? $first
                : new MLNode('cons', $first->position, [$first, $this->pattern()])
        );
    }

    private function patternAtom(): MLNode
    {
        $t = $this->peek();
        if ($t->kind === 'identifier') {
            ++$this->index;
            return new MLNode($t->spelling === '_' ? 'wildcard' : 'name', $t->position, value: $t->spelling);
        }
        if ($this->accept('-') !== null)
            return new MLNode('integer', $t->position, value: -$this->expect('integer')->value);
        if (in_array($t->kind, ['integer', 'string', 'true', 'false'], true))
            return $this->atom();
        if ($this->accept('(') !== null) {
            $first = $this->pattern();
            if ($this->accept(',') !== null) {
                $second = $this->pattern();
                $this->expect(')');
                return new MLNode('pair', $t->position, [$first, $second]);
            }
            $this->expect(')');
            return $first;
        }
        if ($this->accept('[') !== null) {
            $elements = [];
            if ($this->accept(']') === null) {
                $elements[] = $this->pattern();
                while ($this->accept(';') !== null)
                    $elements[] = $this->pattern();
                $this->expect(']');
            }
            return new MLNode('list', $t->position, $elements);
        }
        throw new SyntaxFailure($t);
    }

    private function typeExpression(): MLNode
    {
        $first = $this->listType();
        if ($this->accept('*') !== null)
            $first = new MLNode('pair', $first->position, [$first, $this->listType()]);
        if ($this->accept('->') !== null)
            $first = new MLNode('function', $first->position, [$first, $this->typeExpression()]);
        return $first;
    }

    private function listType(): MLNode
    {
        $e = $this->typeAtom();
        while ($this->peek()->kind === 'identifier' && $this->peek()->spelling === 'list') {
            ++$this->index;
            $e = new MLNode('list', $e->position, [$e]);
        }
        return $e;
    }

    private function typeAtom(): MLNode
    {
        $t = $this->peek();
        if ($t->kind === 'identifier' && in_array($t->spelling, ['int', 'bool', 'string'], true)) {
            ++$this->index;
            return new MLNode($t->spelling, $t->position);
        }
        if ($this->accept('type_variable') !== null)
            return new MLNode('type_variable', $t->position, value: $t->spelling);
        if ($this->accept('(') !== null) {
            $e = $this->typeExpression();
            $this->expect(')');
            return $e;
        }
        throw new SyntaxFailure($t);
    }
}
