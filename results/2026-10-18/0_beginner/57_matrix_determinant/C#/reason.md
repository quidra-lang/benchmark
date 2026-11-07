# Task B selection: 57_matrix_determinant / C#

## Common answer requirements

Use the second row and matching minor at every non-base recursive expansion; flip the sign convention while preserving the base case and integer operations.

## Source evidence

The one-entry branch remains unchanged. In the recursive expansion, select the second-row coefficient and skip exactly that row in the minor, keeping the filter that removes the current column. The recursive call stays at the same site, so every non-base level uses the new row. Reverse the accumulation sign: subtract even zero-based columns and add odd ones, which adds even one-based j. Keep the accumulator and arithmetic integer.

## Minimization

The selected expansion and column filter establish both axes of the minor. The matrices and callers do not change because the same function computes the same determinant; output formatting is independent.

Selected complete lines of `Program.cs`: 7–16. The prior excerpt measured 196 tokens; this excerpt measures 191 with `metric/tokenizer.py`.

## Current token measurement

Task A: **491 tokens**. Task B: **189 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
