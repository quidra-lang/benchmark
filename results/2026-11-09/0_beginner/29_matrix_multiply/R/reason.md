# Task B: 29_matrix_multiply / R

C at row 1, column 2 combines A row [3,-2,5,1] with B column [4,2,-1,7]: products 12,-4,-5,7 sum to 10. Row-major rendering places this value in the second field of the first printed row. The zero at A row 2, column 3 takes ordinary dense matrix-product semantics; there is no source-level conditional that skips a zero multiplicand. A library may choose its own internal implementation, which this source does not expose.

a %*% b is dense matrix multiplication; apply(...,1,...) traverses result rows for formatting.

Evidence is from `main.R`, L1,L2,L3,L4.

- L1: `a <- matrix(c(3, -2, 5, 1, -4, 7, 0, 6, 2, 9, -8, -3), nrow = 3, byrow = TRUE)`
- L2: `b <- matrix(c(1, 4, -5, 2, 6, -1, 0, 7), nrow = 4, byrow = TRUE)`
- L3: `product <- a %*% b`
- L4: `for (i in 1:3) cat(paste(sprintf("%5d", product[i, ]), collapse = ""), "\n", sep = "")`

Minimization: Both operand literals, the matrix product and row rendering establish the requested four pairs, reduction and field position. No helper source is needed for standard dense-multiplication semantics. The selected complete original lines, in source order, cost 179 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 179, and the complete source costs 179. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
