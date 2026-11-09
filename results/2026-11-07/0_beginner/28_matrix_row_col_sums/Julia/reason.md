# Task B: 28_matrix_row_col_sums / Julia

Replace each row sum, column sum and grand total with the respective maximum, leaving the 4×5 entries unchanged. A first-entry or suitably low initial maximum supports the aggregation; do not use an artificial zero for general negative matrices. The first row summary becomes 912. The final summary row becomes `947 765 819 912 720 947`, printed in the same six-character fields as the other four rows. Thus output still has five lines and six fields per line.

Use maximum(row), per-column maximum reductions and maximum(matrix) where sum currently feeds vcat; retain eachrow and %6d rendering.

Evidence is from `main.jl`, L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14.

- L3: `matrix = [125 340 78 912 456; 603 27 819 150 384; 0 765 231 498 62; 947 113 586 39 720]`
- L4: `for row in eachrow(matrix)`
- L5: `row_sum = sum(row)`
- L6: `for value in vcat(row, row_sum)`
- L7: `@printf("%6d", value)`
- L8: `end`
- L9: `println()`
- L10: `end`
- L11: `for value in vcat(vec(sum(matrix; dims = 1)), sum(matrix))`
- L12: `@printf("%6d", value)`
- L13: `end`
- L14: `println()`

Minimization: The matrix literal, aggregation construction and rendering are required for the requested complete change and exact summary values. Imports and wrappers do not contribute to these values. The selected complete original lines, in source order, cost 196 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 196, and the complete source costs 201. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
