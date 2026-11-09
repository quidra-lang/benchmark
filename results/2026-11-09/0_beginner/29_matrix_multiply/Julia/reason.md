# Task B: 29_matrix_multiply / Julia

C at row 1, column 2 combines A row [3,-2,5,1] with B column [4,2,-1,7]: products 12,-4,-5,7 sum to 10. Row-major rendering places this value in the second field of the first printed row. The zero at A row 2, column 3 takes ordinary dense matrix-product semantics; there is no source-level conditional that skips a zero multiplicand. A library may choose its own internal implementation, which this source does not expose.

a*b is ordinary dense matrix multiplication; eachrow and the inner value traversal emit fields in matrix row order.

Evidence is from `main.jl`, L3,L4,L5,L6,L7,L8,L9,L10,L11.

- L3: `a = [3 -2 5 1; -4 7 0 6; 2 9 -8 -3]`
- L4: `b = [1 4; -5 2; 6 -1; 0 7]`
- L5: `product = a * b`
- L6: `for row in eachrow(product)`
- L7: `for value in row`
- L8: `@printf("%5d", value)`
- L9: `end`
- L10: `println()`
- L11: `end`

Minimization: Both operand literals, the matrix product and row rendering establish the requested four pairs, reduction and field position. No helper source is needed for standard dense-multiplication semantics. The selected complete original lines, in source order, cost 117 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 117, and the complete source costs 122. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
