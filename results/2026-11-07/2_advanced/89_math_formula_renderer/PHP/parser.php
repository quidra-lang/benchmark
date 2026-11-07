<?php

const ATOM_KINDS = ['identifier', 'number', 'symbol', 'command', 'text'];

const TERMINATORS = ['}', '&', 'newline', 'right', 'end', 'eof'];

const ARGUMENT_KINDS = [
    ...ATOM_KINDS,
    'eqref',
    '{',
    'frac',
    'binom',
    'overset',
    'underset',
    'sqrt',
    'accent',
];

const UNEXPECTED = [
    'right' => 'unexpected \\right',
    'end' => 'unexpected \\end',
    '&' => 'misplaced &',
    'newline' => 'misplaced \\\\',
];

final readonly class MathNode
{
    public function __construct(
        public string $kind,
        public array $children = [],
        public string|array|null $value = null,
        public int $column = 0,
    ) {}
}

function collapse(array $nodes): MathNode
{
    return count($nodes) === 1 ? $nodes[0] : new MathNode('row', $nodes);
}

function checkBraces(array $tokens): void
{
    $stack = [];
    foreach ($tokens as $t) {
        if ($t->kind === '{')
            $stack[] = $t->column;
        elseif ($t->kind === '}') {
            if (!$stack)
                throw new FormulaError($t->column, 'unmatched }');
            array_pop($stack);
        }
    }
    if ($stack)
        throw new FormulaError($stack[count($stack) - 1], 'unclosed {');
}

final class FormulaParser
{
    private int $position = 0;
    public ?Token $tag = null, $label = null;

    public function __construct(
        private array $tokens,
    ) {}

    private function peek(): Token
    {
        return $this->tokens[$this->position];
    }

    private function take(): Token
    {
        $t = $this->peek();
        if ($t->kind !== 'eof')
            ++$this->position;
        return $t;
    }

    private function unexpected(): never
    {
        $t = $this->peek();
        throw new FormulaError($t->column, UNEXPECTED[$t->kind]);
    }

    public function parse(): array
    {
        $nodes = $this->elementList(true);
        if ($this->peek()->kind !== 'eof')
            $this->unexpected();
        return $nodes;
    }

    private function elementList(bool $top = false, bool $index = false): array
    {
        $nodes = [];
        while (true) {
            $t = $this->peek();
            if (in_array($t->kind, TERMINATORS, true) || $index && $t->kind === 'symbol' && $t->value === ']')
                return $nodes;
            if ($t->kind === 'tag' || $t->kind === 'label') {
                if (!$top)
                    throw new FormulaError($t->column, 'misplaced \\' . $t->kind);
                $kind = $t->kind;
                if ($this->$kind !== null)
                    throw new FormulaError($t->column, 'duplicate \\' . $kind);
                $this->$kind = $this->take();
                continue;
            }
            $nodes[] = $this->element();
        }
    }

    private function element(): MathNode
    {
        $base = in_array($this->peek()->kind, ['^', '_'], true) ? new MathNode('row') : $this->nucleus();
        $sub = $sup = null;
        while (in_array($this->peek()->kind, ['^', '_'], true)) {
            $t = $this->take();
            if ($t->kind === '^') {
                if ($sup !== null)
                    throw new FormulaError($t->column, 'double superscript');
                $sup = $this->argument('^');
            } else {
                if ($sub !== null)
                    throw new FormulaError($t->column, 'double subscript');
                $sub = $this->argument('_');
            }
        }
        return $sub === null && $sup === null ? $base : new MathNode('script', [$base, $sub, $sup]);
    }

    private function argument(string $name): MathNode
    {
        if (!in_array($this->peek()->kind, ARGUMENT_KINDS, true))
            throw new FormulaError($this->peek()->column, 'missing argument for ' . $name);
        return $this->nucleus();
    }

    private function delimiter(): string
    {
        $t = $this->take();
        if (
            $t->kind === 'symbol' && in_array($t->value, ['(', ')', '[', ']', '|', '.'], true)
            || $t->kind === 'command' && in_array($t->value, ['\\{', '\\}'], true)
        )
            return $t->value;
        throw new FormulaError($t->column, 'invalid delimiter');
    }

    private function nucleus(): MathNode
    {
        $t = $this->take();
        $kind = $t->kind;
        if (in_array($kind, ATOM_KINDS, true))
            return new MathNode($kind, value: $t->value, column: $t->column);
        if ($kind === 'eqref')
            return new MathNode('reference', value: $t->value, column: $t->column);
        if ($kind === '{') {
            $nodes = $this->elementList();
            if ($this->peek()->kind !== '}')
                $this->unexpected();
            $this->take();
            return collapse($nodes);
        }
        if (in_array($kind, ['frac', 'binom', 'overset', 'underset'], true)) {
            $a = $this->argument('\\' . $kind);
            $b = $this->argument('\\' . $kind);
            return new MathNode($kind, [$a, $b]);
        }
        if ($kind === 'sqrt') {
            $index = null;
            if ($this->peek()->kind === 'symbol' && $this->peek()->value === '[') {
                $opening = $this->take();
                $nodes = $this->elementList(index: true);
                if ($this->peek()->kind !== 'symbol' || $this->peek()->value !== ']')
                    throw new FormulaError($opening->column, 'missing ]');
                $this->take();
                $index = collapse($nodes);
            }
            $body = $this->argument('\\sqrt');
            return $index === null ? new MathNode('sqrt', [$body]) : new MathNode('root', [$index, $body]);
        }
        if ($kind === 'accent')
            return new MathNode('accent', [$this->argument('\\' . $t->value)], $t->value);
        if ($kind === 'left') {
            $left = $this->delimiter();
            $nodes = $this->elementList();
            if ($this->peek()->kind !== 'right')
                throw new FormulaError($t->column, 'missing \\right');
            $closing = $this->take();
            $right = $this->delimiter();
            return new MathNode('delim', [collapse($nodes)], [$left, $right], $closing->column);
        }
        return $this->matrix($t->value, $t->column);
    }

    private function matrix(string $environment, int $column): MathNode
    {
        $rows = [[]];
        while (true) {
            $rows[count($rows) - 1][] = collapse($this->elementList());
            $t = $this->take();
            if ($t->kind === '&')
                continue;
            if ($t->kind === 'newline') {
                $rows[] = [];
                continue;
            }
            if ($t->kind !== 'end')
                throw new FormulaError($column, 'missing \\end');
            if ($t->value !== $environment)
                throw new FormulaError($t->column, 'mismatched \\end');
            break;
        }
        $last = $rows[count($rows) - 1];
        if (count($rows) >= 2 && count($last) === 1 && $last[0]->kind === 'row' && !$last[0]->children)
            array_pop($rows);
        $columns = max(array_map(count(...), $rows));
        foreach ($rows as &$row)
            while (count($row) < $columns)
                $row[] = new MathNode('row');
        unset($row);
        return new MathNode('matrix', $rows, $environment);
    }
}
