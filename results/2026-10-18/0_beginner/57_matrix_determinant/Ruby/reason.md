# Task B selection: 57_matrix_determinant / Ruby

## Common answer requirements

Use the second row and matching minor at every non-base recursive expansion; flip the sign convention while preserving the base case and integer operations.

## Source evidence

The one-entry branch remains unchanged. In the recursive expansion, select the second-row coefficient and skip exactly that row in the minor, keeping the filter that removes the current column. The recursive call stays at the same site, so every non-base level uses the new row. Reverse the accumulation sign: subtract even zero-based columns and add odd ones, which adds even one-based j. Keep the accumulator and arithmetic integer.

## Minimization

The selected expansion and column filter establish both axes of the minor. The matrices and callers do not change because the same function computes the same determinant; output formatting is independent.

Selected complete lines of `main.rb`: 1–6. The prior excerpt measured 126 tokens; this excerpt measures 121 with `metric/tokenizer.py`.
