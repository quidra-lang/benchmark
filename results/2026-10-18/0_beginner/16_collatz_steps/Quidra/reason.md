# Task B selection for 16_collatz_steps in Quidra

## Common answer requirements

1. Explain why start 1 has zero operations but an initial maximum of one.
2. Trace start 6, deriving its operation count and maximum.
3. Identify how the starting value enters the maximum before operations are counted.

## Evidence and answer

The declaration `n, steps, largest := start, 0, start` initializes `n` and `largest` from `start` and sets `steps` to zero before the loop. For start 1, the guard immediately fails, leaving zero operations and a maximum of 1. For start 6, the updates produce 3, 10, 5, 16, 8, 4, 2, and 1. The step increment counts eight operations, and the maximum update records 16.

## Selection and minimization

The excerpt copies lines 2–7 of `main.qui`. It keeps the initialization, stopping condition, recurrence, and updates for both reported values. The question supplies the two starts, so the input traversal and the final display are omitted.

`metric/tokenizer.py` reports 142 source tokens for Task A and 93 for Task B.
