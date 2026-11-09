<?php

function evaluate(string $expression): string
{
    $stack = [];
    foreach (explode(' ', $expression) as $token) {
        if (in_array($token, ['+', '-', '*', '/'], true)) {
            if (count($stack) < 2) {
                return 'error: stack underflow';
            }
            $b = array_pop($stack);
            $a = array_pop($stack);
            if ($token === '/' && $b === 0) {
                return 'error: division by zero';
            }
            $stack[] = match ($token) {
                '+' => $a + $b,
                '-' => $a - $b,
                '*' => $a * $b,
                '/' => intdiv($a, $b),
            };
        } else {
            $stack[] = (int) $token;
        }
    }
    return count($stack) === 1 ? (string) $stack[0] : 'error: leftover operands';
}

$expressions = [
    '3 4 + 2 *', '-17 5 / 4 -3 * -', '1 2 + * 3', '15 7 1 1 + - / 3 * 2 1 1 + + -',
    '4 2 5 * + 1 3 2 * - 5 + /', '2 3 4 + 5', '46341 46339 * -2 /',
];
foreach ($expressions as $expression) {
    printf("%s => %s\n", $expression, evaluate($expression));
}
