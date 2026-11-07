# Task B: 28_matrix_row_col_sums / R

Replace each row sum, column sum and grand total with the respective maximum, leaving the 4×5 entries unchanged. A first-entry or suitably low initial maximum supports the aggregation; do not use an artificial zero for general negative matrices. The first row summary becomes 912. The final summary row becomes `947 765 819 912 720 947`, printed in the same six-character fields as the other four rows. Thus output still has five lines and six fields per line.

Replace addmargins default sums with a maximum aggregation (or construct row/column/whole maxima explicitly), then retain the six-width row rendering.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10.

- L1: `matrix_values <- matrix(c(`
- L2: `125, 340, 78, 912, 456,`
- L3: `603, 27, 819, 150, 384,`
- L4: `0, 765, 231, 498, 62,`
- L5: `947, 113, 586, 39, 720`
- L6: `), nrow = 4, byrow = TRUE)`
- L7: `totals <- addmargins(matrix_values)`
- L8: `for (i in seq_len(nrow(totals))) {`
- L9: `cat(paste(sprintf("%6d", totals[i, ]), collapse = ""), "\n", sep = "")`
- L10: `}`

Minimization: The matrix literal, aggregation construction and rendering are required for the requested complete change and exact summary values. Imports and wrappers do not contribute to these values. The selected complete original lines, in source order, cost 204 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 204, and the complete source costs 204. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
