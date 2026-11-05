# Task B selection: 06_factorial_table / Quidra

## Common answer requirements

1. Locate the range endpoint and identify the representation used for the factorial.
2. Explain how to print sixteen rows in order with exact decimal values through `15!`.

## Source evidence and minimization

Line 1 of `main.qui` gives the inclusive upper bound. The omitted lower bound
defaults to zero, and the integer literal bound infers an arbitrary-precision
`int` for `n`. Raising the upper bound to `15` gives sixteen rows in order.

Line 2 shows that the value printed is `n!`. The factorial operator preserves
the type of `n`, and integer interpolation prints the result in decimal.
The existing `int` holds `15!` (`1307674368000`) exactly, so the range bound is
the only required change.

The range header alone gives the bounds and operand type. The print line
supplies the factorial expression and shows how its result is printed.
The excerpt needs both lines and copies them verbatim in source order.

The repository tokenizer counts 27 tokens for Task A and 27 for Task B.
The factorial syntax is specified for Core `develop`. Compiler support is
pending.
