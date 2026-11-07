<?php

const LEVELS = [
    ['||'],
    ['&&'],
    ['|'],
    ['^'],
    ['&'],
    ['==', '!='],
    ['<', '>', '<=', '>='],
    ['<<', '>>'],
    ['+', '-'],
    ['*', '/', '%'],
];

final class ExpressionError extends RuntimeException {}

function integerValue(string $spelling): int
{
    $value = $spelling;
    foreach (['ll', 'LL', 'l', 'L'] as $suffix)
        if (str_ends_with($value, $suffix) && strlen($value) > strlen($suffix)) {
            $value = substr($value, 0, -strlen($suffix));
            break;
        }
    if (preg_match('/^0[xX][0-9a-fA-F]+$/D', $value)) {
        $digits = substr($value, 2);
        $base = 16;
    } elseif (preg_match('/^0[0-7]*$/D', $value)) {
        $digits = $value;
        $base = 8;
    } elseif (preg_match('/^[1-9][0-9]*$/D', $value)) {
        $digits = $value;
        $base = 10;
    } else
        throw new ExpressionError('invalid integer constant "' . $spelling . '"');
    $v = 0;
    foreach (str_split(strtolower($digits)) as $c)
        $v = ($v * $base) + (ctype_digit($c) ? ord($c) - 48 : ord($c) - 87);
    return $v;
}

function characterValue(string $spelling): int
{
    $v = substr($spelling, 1, -1);
    if (strlen($v) === 1 && $v !== "'" && $v !== '\\')
        return ord($v);
    $escapes = ['n' => 10, 't' => 9, '\\' => 92, "'" => 39, '"' => 34, '0' => 0];
    if (strlen($v) === 2 && $v[0] === '\\' && isset($escapes[$v[1]]))
        return $escapes[$v[1]];
    throw new ExpressionError('invalid character constant ' . $spelling);
}

final class ExpressionParser
{
    private int $index = 0;

    public function __construct(
        private array $tokens,
    ) {}

    private function peek(): ?string
    {
        return $this->tokens[$this->index]->spelling ?? null;
    }

    public function parse(string $directive): array
    {
        if (!$this->tokens)
            throw new ExpressionError("#$directive with no expression");
        $tree = $this->expression();
        if ($this->peek() !== null)
            throw new ExpressionError('missing binary operator before "' . $this->peek() . '"');
        return $tree;
    }

    private function expression(): array
    {
        $left = $this->binary(0);
        if ($this->peek() === '?') {
            ++$this->index;
            $yes = $this->expression();
            if ($this->peek() !== ':')
                throw new ExpressionError("'?' without following ':'");
            ++$this->index;
            return ['conditional', $left, $yes, $this->expression()];
        }
        return $left;
    }

    private function binary(int $level): array
    {
        if ($level === count(LEVELS))
            return $this->unary();
        $left = $this->binary($level + 1);
        while (in_array($this->peek(), LEVELS[$level], true)) {
            $op = $this->peek();
            ++$this->index;
            $left = ['binary', $op, $left, $this->binary($level + 1)];
        }
        return $left;
    }

    private function unary(): array
    {
        $op = $this->peek();
        if (in_array($op, ['+', '-', '!', '~'], true)) {
            ++$this->index;
            return ['unary', $op, $this->unary()];
        }
        if (!isset($this->tokens[$this->index]))
            throw new ExpressionError('expected value at end of expression');
        $t = $this->tokens[$this->index++];
        if ($t->kind === 'number')
            return ['constant', integerValue($t->spelling)];
        if ($t->kind === 'character')
            return ['constant', characterValue($t->spelling)];
        if ($t->kind === 'identifier')
            return ['identifier', $t->spelling];
        if ($t->spelling === '(') {
            $v = $this->expression();
            if ($this->peek() !== ')')
                throw new ExpressionError("missing ')' in expression");
            ++$this->index;
            return $v;
        }
        throw new ExpressionError('expected value before "' . $t->spelling . '"');
    }
}

function evaluateExpression(array $t, callable $warning): int
{
    if ($t[0] === 'constant')
        return $t[1];
    if ($t[0] === 'identifier') {
        $warning('identifier "' . $t[1] . '" evaluates to 0');
        return 0;
    }
    if ($t[0] === 'unary') {
        $a = evaluateExpression($t[2], $warning);
        return match ($t[1]) {
            '+' => $a,
            '-' => -$a,
            '!' => (int) ($a === 0),
            default => -$a - 1,
        };
    }
    if ($t[0] === 'conditional')
        return evaluateExpression(evaluateExpression($t[1], $warning) !== 0 ? $t[2] : $t[3], $warning);
    $a = evaluateExpression($t[2], $warning);
    if ($t[1] === '&&')
        return $a === 0 ? 0 : (int) (evaluateExpression($t[3], $warning) !== 0);
    if ($t[1] === '||')
        return $a !== 0 ? 1 : (int) (evaluateExpression($t[3], $warning) !== 0);
    $b = evaluateExpression($t[3], $warning);
    if (($t[1] === '/' || $t[1] === '%') && $b === 0)
        throw new ExpressionError('division by zero in #if');
    return match ($t[1]) {
        '+' => $a + $b,
        '-' => $a - $b,
        '*' => $a * $b,
        '/' => intdiv($a, $b),
        '%' => $a % $b,
        '<<' => $a << $b,
        '>>' => $a >> $b,
        '&' => $a & $b,
        '|' => $a | $b,
        '^' => $a ^ $b,
        '==' => (int) ($a === $b),
        '!=' => (int) ($a !== $b),
        '<' => (int) ($a < $b),
        '>' => (int) ($a > $b),
        '<=' => (int) ($a <= $b),
        '>=' => (int) ($a >= $b),
    };
}
