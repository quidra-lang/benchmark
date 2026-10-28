<?php

const KINDS = ['copy', 'bin', 'load', 'store', 'goto', 'if', 'param', 'call', 'return', 'read', 'print'];

final readonly class TacInstruction
{
    public function __construct(
        public string $kind,
        public ?string $destination = null,
        public int|string|null $a = null,
        public int|string|null $b = null,
        public ?string $operation = null,
        public ?string $name = null,
        public int $count = 0,
    ) {}

    public function operandFields(): array
    {
        return match ($this->kind) {
            'bin', 'if', 'store' => ['a', 'b'],
            'copy', 'load', 'param', 'print' => ['a'],
            'return' => $this->a === null ? [] : ['a'],
            default => [],
        };
    }

    public function usedVariables(): array
    {
        $r = [];
        foreach ($this->operandFields() as $field)
            if (is_string($this->{$field}))
                $r[] = $this->{$field};
        return $r;
    }

    public function expression(): ?array
    {
        return match ($this->kind) {
            'bin' => ['bin', $this->operation, $this->a, $this->b],
            'load' => ['load', $this->name, $this->a],
            default => null,
        };
    }

    public function changed(array $fields): self
    {
        return new self(...array_replace([
            'kind' => $this->kind,
            'destination' => $this->destination,
            'a' => $this->a,
            'b' => $this->b,
            'operation' => $this->operation,
            'name' => $this->name,
            'count' => $this->count,
        ], $fields));
    }
}

final class TacFunction
{
    public int $temporarySerial = 0, $preheaderSerial = 0;

    public function __construct(
        public string $name,
        public array $parameters,
        public array $code = [],
    ) {}

    public function copy(): self
    {
        return new self($this->name, $this->parameters, $this->code);
    }

    public function instructions(): array
    {
        return array_values(array_filter($this->code, fn($x) => $x instanceof TacInstruction));
    }
}

final class TacProgram
{
    public function __construct(
        public array $arrays,
        public array $functions,
    ) {}
}

function operand(string $word): int|string
{
    return $word[0] === '-' || ctype_digit($word[0]) ? (int) $word : $word;
}

function arrayOperand(string $word): array
{
    [$name, $index] = explode('[', substr($word, 0, -1), 2);
    return [$name, operand($index)];
}

function parseInstruction(array $w): TacInstruction
{
    $first = $w[0];
    if ($first === 'goto')
        return new TacInstruction('goto', name: $w[1]);
    if ($first === 'if')
        return new TacInstruction('if', a: operand($w[1]), b: operand($w[3]), operation: $w[2], name: $w[5]);
    if ($first === 'param' || $first === 'print')
        return new TacInstruction($first, a: operand($w[1]));
    if ($first === 'return')
        return new TacInstruction('return', a: count($w) === 2 ? operand($w[1]) : null);
    if ($first === 'read')
        return new TacInstruction('read', $w[1]);
    if ($first === 'call')
        return new TacInstruction('call', name: $w[1], count: (int) $w[2]);
    if (str_contains($first, '[')) {
        [$name, $index] = arrayOperand($first);
        return new TacInstruction('store', a: $index, b: operand($w[2]), name: $name);
    }
    if ($w[2] === 'call')
        return new TacInstruction('call', $first, name: $w[3], count: (int) $w[4]);
    if (count($w) === 5)
        return new TacInstruction('bin', $first, operand($w[2]), operand($w[4]), $w[3]);
    if (str_contains($w[2], '[')) {
        [$name, $index] = arrayOperand($w[2]);
        return new TacInstruction('load', $first, $index, name: $name);
    }
    return new TacInstruction('copy', $first, operand($w[2]));
}

function readProgram(): TacProgram
{
    $arrays = $functions = [];
    $current = null;
    foreach (file('input/program.tac', FILE_IGNORE_NEW_LINES) as $line) {
        $w = preg_split('/ +/', trim($line), -1, PREG_SPLIT_NO_EMPTY);
        if (!$w || str_starts_with($w[0], '#'))
            continue;
        if ($w[0] === 'array')
            $arrays[] = [$w[1], (int) $w[2]];
        elseif ($w[0] === 'func') {
            $current = new TacFunction($w[1], array_slice($w, 2));
            $functions[] = $current;
        } elseif ($w[0] === 'end')
            $current = null;
        elseif (count($w) === 1 && str_ends_with($w[0], ':'))
            $current->code[] = substr($w[0], 0, -1);
        else
            $current->code[] = parseInstruction($w);
    }
    return new TacProgram($arrays, $functions);
}

function calculate(string $op, int $a, int $b): int
{
    return match ($op) {
        '+' => $a + $b,
        '-' => $a - $b,
        '*' => $a * $b,
        '/' => intdiv($a, $b),
        '%' => $a % $b,
        '<' => (int) ($a < $b),
        '<=' => (int) ($a <= $b),
        '>' => (int) ($a > $b),
        '>=' => (int) ($a >= $b),
        '==' => (int) ($a === $b),
        '!=' => (int) ($a !== $b),
    };
}

function expressionString(array $e): string
{
    return $e[0] === 'load' ? $e[1] . '[' . $e[2] . ']' : $e[2] . $e[1] . $e[3];
}

function instructionString(TacInstruction $i): string
{
    return match ($i->kind) {
        'copy' => "{$i->destination} = {$i->a}",
        'bin' => "{$i->destination} = {$i->a} {$i->operation} {$i->b}",
        'load' => "{$i->destination} = {$i->name}[{$i->a}]",
        'store' => "{$i->name}[{$i->a}] = {$i->b}",
        'goto' => 'goto ' . $i->name,
        'if' => "if {$i->a} {$i->operation} {$i->b} goto {$i->name}",
        'call' => ($i->destination === null ? '' : $i->destination . ' = ') . "call {$i->name} {$i->count}",
        'read' => 'read ' . $i->destination,
        'return' => $i->a === null ? 'return' : 'return ' . $i->a,
        default => $i->kind . ' ' . $i->a,
    };
}

function functionLines(TacFunction $f): array
{
    $out = [implode(' ', ['func', $f->name, ...$f->parameters])];
    foreach ($f->code as $line)
        $out[] = is_string($line) ? $line . ':' : '    ' . instructionString($line);
    $out[] = 'end';
    return $out;
}

function programLines(TacProgram $p): array
{
    $out = [];
    foreach ($p->arrays as [$name, $size])
        $out[] = "array $name $size";
    foreach ($p->functions as $f) {
        if ($out)
            $out[] = '';
        array_push($out, ...functionLines($f));
    }
    return $out;
}
