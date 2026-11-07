# Task B selection — 93_sudoku_solver / Python

## Common answer requirements

Locate the candidate enumeration and reverse it to 9 through 1. Keep the next-cell choice, successful-write count, backtracking and first-solution termination.

## Source evidence

The range beginning at 1 with exclusive stop 10 is the candidate order. Change it to a descending range starting at 9 with exclusive stop 0 and a negative step.

## Minimization

Selected complete lines of `main.py`: L22. The change affects only the enumeration. The wider recursive body, puzzle data and output would provide context about unchanged behavior but do not locate any other edit.

The selected excerpt measures **19 tokens** with `metric/tokenizer.py`.

## Current token measurement

Task A: **538 tokens**. Task B: **19 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
