# Task B selection — 99_expression_evaluator / Python

## Common answer requirements

Locate the division operation and floor its signed quotient, preserving the order of operand evaluation, precedence, first errors, and commit-on-success assignments.

## Source evidence

The existing int conversion truncates the quotient toward zero. Floor division of the already evaluated integer operands implements the requested rounding at this site, including negative nonintegral quotients.

## Minimization

Selected complete lines of `main.py`: L39. The selected quotient operation locates the only edit. The wider parser context establishes unchanged processing but the local replacement preserves the existing zero check, operand reads, error handling and assignment logic.

The selected excerpt measures **17 tokens** with `metric/tokenizer.py`.
