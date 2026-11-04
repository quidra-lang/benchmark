# Task B selection — 99_expression_evaluator / C#

## Common answer requirements

Locate the division operation and floor its signed quotient, preserving the order of operand evaluation, precedence, first errors and commit-on-success assignments.

## Source evidence

The declarations or typed operand producer establish signed integer operands. Replace the quotient operation in place with integer floor division. With a truncating quotient and remainder, decrement the quotient only when the remainder is nonzero and the operands have opposite signs. The operand values are already available and need no re-evaluation.

## Minimization

Selected complete lines of `Program.cs`: L72, L76, L78. The division operation and just enough operand-type evidence identify the correct integer operation. A bare slash would also be consistent with floating-point division. The surrounding precedence, zero-divisor check, error handling and assignment logic are unaffected by this local edit.

The selected excerpt measures **59 tokens** with `metric/tokenizer.py`.
