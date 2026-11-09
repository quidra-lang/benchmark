# Task B: 28_matrix_row_col_sums / J

Replace each row sum, column sum and grand total with the respective maximum, leaving the 4×5 entries unchanged. A first-entry or suitably low initial maximum supports the aggregation; do not use an artificial zero for general negative matrices. The first row summary becomes 912. The final summary row becomes `947 765 819 912 720 947`, printed in the same six-character fields as the other four rows. Thus output still has five lines and six fields per line.

Replace +/ row/column reductions and whole-matrix sum in result construction with maximum reductions (>./); the 6.0 format continues to render all six fields.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5.

- L1: `matrix =: 4 5$125 340 78 912 456 603 27 819 150 384 0 765 231 498 62 947 113 586 39 720`
- L2: `rows =: matrix,.+/"1 matrix`
- L3: `columns =: +/matrix`
- L4: `result =: rows, columns,+/columns`
- L5: `smoutput '6.0' 8!:2 result`

Minimization: The matrix literal, aggregation construction and rendering are required for the requested complete change and exact summary values. Imports and wrappers do not contribute to these values. The selected complete original lines, in source order, cost 130 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 130, and the complete source costs 130. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
