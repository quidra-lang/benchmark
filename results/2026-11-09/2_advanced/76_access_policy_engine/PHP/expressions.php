<?php

function tokenizeExpression(string $text): array
{
    preg_match_all('/"[^"]*"|[0-9]+|[A-Za-z][A-Za-z0-9_.]*|==|!=|<=|>=|[()\[\],+*<>-]/', $text, $matches);
    return $matches[0];
}

class ExpressionParser
{
    private array $tokens;
    private int $position = 0;

    public function __construct(string $text)
    {
        $this->tokens = tokenizeExpression($text);
    }

    private function peek(): ?string
    {
        return $this->tokens[$this->position] ?? null;
    }

    private function take(): string
    {
        return $this->tokens[$this->position++];
    }

    private function chain(callable $read, array $operators): object
    {
        $expression = $read();
        while (in_array($this->peek(), $operators, true)) {
            $operation = $this->take();
            $expression = (object) ['kind' => 'operation', 'operation' => $operation, 'arguments' => [$expression, $read()]];
        }
        return $expression;
    }

    public function disjunction(): object
    {
        return $this->chain(fn() => $this->conjunction(), ['or']);
    }

    private function conjunction(): object
    {
        return $this->chain(fn() => $this->negation(), ['and']);
    }

    private function negation(): object
    {
        if ($this->peek() !== 'not') {
            return $this->comparison();
        }
        $this->take();
        return (object) ['kind' => 'operation', 'operation' => 'not', 'arguments' => [$this->negation()]];
    }

    private function comparison(): object
    {
        $left = $this->sum();
        if (!in_array($this->peek(), ['==', '!=', '<', '<=', '>', '>=', 'in'], true)) {
            return $left;
        }
        $operation = $this->take();
        return (object) ['kind' => 'operation', 'operation' => $operation, 'arguments' => [$left, $this->sum()]];
    }

    private function sum(): object
    {
        return $this->chain(fn() => $this->product(), ['+', '-']);
    }

    private function product(): object
    {
        return $this->chain(fn() => $this->unary(), ['*']);
    }

    private function unary(): object
    {
        if ($this->peek() !== '-') {
            return $this->primary();
        }
        $this->take();
        return (object) ['kind' => 'operation', 'operation' => '-', 'arguments' => [$this->unary()]];
    }

    private function primary(): object
    {
        $token = $this->take();
        if ($token === '(') {
            $expression = $this->disjunction();
            $this->take();
            return $expression;
        }
        if ($token === '[') {
            $value = [];
            if ($this->peek() !== ']') {
                while (true) {
                    $value[] = substr($this->take(), 1, -1);
                    if ($this->peek() !== ',') {
                        break;
                    }
                    $this->take();
                }
            }
            $this->take();
            return (object) ['kind' => 'literal', 'value' => $value];
        }
        if (str_starts_with($token, '"')) {
            return (object) ['kind' => 'literal', 'value' => substr($token, 1, -1)];
        }
        if (preg_match('/^[0-9]+$/', $token)) {
            return (object) ['kind' => 'literal', 'value' => (int) $token];
        }
        if ($token === 'true' || $token === 'false') {
            return (object) ['kind' => 'literal', 'value' => $token === 'true'];
        }
        if ($token === 'it') {
            return (object) ['kind' => 'it'];
        }
        if (str_contains($token, '.')) {
            return (object) ['kind' => 'attribute', 'name' => $token];
        }
        $this->take();
        $arguments = [];
        if ($this->peek() !== ')') {
            while (true) {
                $arguments[] = $this->disjunction();
                if ($this->peek() !== ',') {
                    break;
                }
                $this->take();
            }
        }
        $this->take();
        return (object) ['kind' => 'operation', 'operation' => $token, 'arguments' => $arguments];
    }
}

function parseExpression(string $text): object
{
    return (new ExpressionParser($text))->disjunction();
}
