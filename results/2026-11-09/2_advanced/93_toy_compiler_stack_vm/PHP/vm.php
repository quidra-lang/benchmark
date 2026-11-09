<?php

const MIN_INT = -2147483648;

const MAX_INT = 2147483647;

const BINARY_OPS = ['ADD', 'SUB', 'MUL', 'DIV', 'MOD', 'LT', 'LE', 'GT', 'GE', 'EQ', 'NE'];

final class RuntimeFault extends RuntimeException {}

function calculate(string $op, int $a, ?int $b = null): int
{
    if (($op === 'DIV' || $op === 'MOD') && $b === 0)
        throw new RuntimeFault('division by zero');
    $r = match ($op) {
        'ADD' => $a + $b,
        'SUB' => $a - $b,
        'MUL' => $a * $b,
        'DIV' => intdiv($a, $b),
        'MOD' => $a % $b,
        'NEG' => -$a,
        'NOT' => (int) ($a === 0),
        'LT' => (int) ($a < $b),
        'LE' => (int) ($a <= $b),
        'GT' => (int) ($a > $b),
        'GE' => (int) ($a >= $b),
        'EQ' => (int) ($a === $b),
        'NE' => (int) ($a !== $b),
    };
    if ($r < MIN_INT || $r > MAX_INT)
        throw new RuntimeFault('integer overflow');
    return $r;
}

final class VmFrame
{
    public function __construct(
        public array $locals,
        public int $returnAddress,
    ) {}
}

final class Execution
{
    public array $globals, $stack = [], $frames = [], $counts, $calls = [], $pairs = [], $output = [];
    public int $readPosition = 0, $pc = 0, $executed = 0, $maxStack = 0, $maxDepth = 0;
    public ?string $error = null;
    public ?int $errorPc = null;

    public function __construct(
        private array $code,
        private array $owners,
        private array $starts,
        int $globalSize,
        private array $inputs,
    ) {
        $this->globals = array_fill(0, $globalSize, 0);
        $this->counts = array_fill(0, count($code), 0);
    }

    private function step(): bool
    {
        $instruction = $this->code[$this->pc];
        $op = $instruction->op;
        $args = $instruction->args;
        $next = $this->pc + 1;
        $frame = count($this->frames) - 1;
        switch ($op) {
            case 'PUSH':
                $this->stack[] = $args[0];
                break;
            case 'POP':
                array_pop($this->stack);
                break;
            case 'LOADG':
                $this->stack[] = $this->globals[$args[0]];
                break;
            case 'STOREG':
                $this->globals[$args[0]] = array_pop($this->stack);
                break;
            case 'LOADL':
                $this->stack[] = $this->frames[$frame]->locals[$args[0]];
                break;
            case 'STOREL':
                $this->frames[$frame]->locals[$args[0]] = array_pop($this->stack);
                break;
            case 'LOADA':
            case 'STOREA':
                if ($op === 'STOREA')
                    $value = array_pop($this->stack);
                $index = array_pop($this->stack);
                [$address, $size] = $args;
                if ($index < 0 || $index >= $size)
                    throw new RuntimeFault("index $index out of bounds for array of size $size");
                if ($op === 'LOADA')
                    $this->stack[] = $this->globals[$address + $index];
                else
                    $this->globals[$address + $index] = $value;
                break;
            case 'ADD':
            case 'SUB':
            case 'MUL':
            case 'DIV':
            case 'MOD':
            case 'LT':
            case 'LE':
            case 'GT':
            case 'GE':
            case 'EQ':
            case 'NE':
                $b = array_pop($this->stack);
                $a = array_pop($this->stack);
                $this->stack[] = calculate($op, $a, $b);
                break;
            case 'NEG':
            case 'NOT':
                $value = array_pop($this->stack);
                $this->stack[] = calculate($op, $value);
                break;
            case 'JUMP':
                $next = $args[0];
                break;
            case 'JUMPF':
            case 'JUMPT':
                $v = array_pop($this->stack);
                if (($v === 0) === ($op === 'JUMPF'))
                    $next = $args[0];
                break;
            case 'CALL':
                if (count($this->frames) === 100)
                    throw new RuntimeFault('call depth limit exceeded');
                [$target, $count] = $args;
                $values = $count === 0 ? [] : array_splice($this->stack, -$count);
                $this->frames[] = new VmFrame($values, $next);
                $callee = $this->starts[$target];
                $this->calls[$callee] = ($this->calls[$callee] ?? 0) + 1;
                $caller = $this->owners[$this->pc];
                $this->pairs[$caller][$callee] = ($this->pairs[$caller][$callee] ?? 0) + 1;
                $next = $target;
                break;
            case 'ENTER':
                $local = $this->frames[$frame]->locals;
                $this->frames[$frame]->locals = [...$local, ...array_fill(0, $args[0] - count($local), 0)];
                break;
            case 'RET':
            case 'RETV':
                $next = array_pop($this->frames)->returnAddress;
                break;
            case 'READ':
                if ($this->readPosition === count($this->inputs))
                    throw new RuntimeFault('read past end of input');
                $this->stack[] = $this->inputs[$this->readPosition++];
                break;
            case 'PRINT':
                $values = array_splice($this->stack, -$args[0]);
                $this->output[] = implode(' ', $values);
                break;
        }
        $this->maxStack = max($this->maxStack, count($this->stack));
        $this->maxDepth = max($this->maxDepth, count($this->frames));
        $this->pc = $next;
        return $op !== 'HALT';
    }

    public function run(): self
    {
        while (true) {
            if ($this->executed === 100000) {
                $this->error = 'instruction limit exceeded';
                $this->errorPc = $this->pc;
                break;
            }
            ++$this->executed;
            ++$this->counts[$this->pc];
            try {
                if (!$this->step())
                    break;
            } catch (RuntimeFault $e) {
                $this->error = $e->getMessage();
                $this->errorPc = $this->pc;
                break;
            }
        }
        return $this;
    }
}
