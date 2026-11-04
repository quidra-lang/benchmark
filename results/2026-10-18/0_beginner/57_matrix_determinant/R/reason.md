# Task B selection: 57_matrix_determinant / R

## Common answer requirements

Use the second row and matching minor at every non-base recursive expansion; flip the sign convention while preserving the base case and integer operations.

## Source evidence

The one-entry branch remains unchanged. In the recursive expansion, select the second-row coefficient and skip exactly that row in the minor, keeping the filter that removes the current column. The recursive call stays at the same site, so every non-base level uses the new row. Reverse the accumulation sign: add even one-based columns and subtract odd ones. Keep the accumulator and arithmetic integer.

## Minimization

The selected expansion and column filter establish both axes of the minor. The matrices and callers do not change because the same function computes the same determinant; output formatting is independent.

Selected complete lines of `main.R`: 1–9. The prior excerpt measured 145 tokens; this excerpt measures 140 with `metric/tokenizer.py`.
