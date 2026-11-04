# Task B selection: 99_expression_evaluator / Quidra

## Common answer requirements

Change only quotient rounding to floor while preserving multiplication precedence, left-to-right operand evaluation, and first-error behavior.

## Source evidence

The multiplicative parser seeds its running value from the left operand and consumes one right operand per operator. The zero-divisor check precedes the division. Replace only the quotient computation with exact integer floor division, using an exact signed-remainder correction if needed. Keep token advancement, both operand reads, the zero check, and error propagation as written.

## Minimization

The multiplicative loop establishes where rounding changes and why the operand order and zero-error ordering do not. The enclosing additive parser and assignment updates need no change. Selected complete lines of `main.qui`: 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38.
