# Task B selection: 28_matrix_row_col_sums / Quidra

## Answer requirements

Suppose row sums, column sums and the grand total are replaced with the corresponding row maxima, column maxima and whole-matrix maximum. Explain the complete change from the stored 4-by-5 matrix through initialization and aggregation to the five-line, six-field output. Derive the first row's new summary field and the complete final summary row, and identify how original matrix entries and six-character field formatting remain intact.

## Answer and source evidence

Replace row sum, per-column accumulation and final aggregate by maxima. Initialize from existing row/column values rather than additive zero so the operation remains meaningful for negative entries. Preserve matrix entries, row order and six-character right-aligned output. The first row summary is 912. The final row values are 947,765,819,912,720,947 (each in a six-character field). Four original rows plus that summary still produce five lines with six fields.

The columns accumulator needs a first-row or appropriate maximum initialization and elementwise maximum updates; row_sum becomes a maximum, and columns.sum becomes columns.max.

Selected `main.qui` lines: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
