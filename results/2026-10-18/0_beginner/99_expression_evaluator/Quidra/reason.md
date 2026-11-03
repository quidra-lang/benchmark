# Task B selection — 99_expression_evaluator / Quidra

The accumulator and right operand are signed integers obtained by evaluating the left operand and the next unary operand in their existing order. Change the division update so a negative nonintegral mathematical quotient is rounded down. After the existing zero-divisor guard, compute the truncated quotient and decrement it only when the operand signs differ and the division has a nonzero remainder. Retain the accumulator update at the same point, leaving error propagation, precedence and the assignment path intact. The separate typed unary-negation temporary is retained for the pinned backend's union-return lowering.

Selected complete source lines in order are 25, 31, 37.

Tokenizer: Task A 1029 tokens; Task B 52 tokens.
