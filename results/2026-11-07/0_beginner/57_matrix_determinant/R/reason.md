# Task B: 57_matrix_determinant / R

The one-entry base returns that entry. Each first-row column creates a minor by deleting the first row and that column, recursively evaluates it, multiplies by the corresponding first-row entry and adds/subtracts with alternating signs. For matrix 1 the first term is 2×det[[4,-2],[6,3]]=2×24=48. There is no division or pre-output rounding: all signed terms and the result remain exact integers for these inputs.

The matrices explicitly use as.integer and total begins at 0L; integer products/sums retain exact signed values for these small examples. There is no mathematical or runtime conversion to fractional arithmetic in the determinant.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L14,L15,L21.

- L1: `laplace <- function(values) {`
- L2: `n <- nrow(values)`
- L3: `if (n == 1) {`
- L4: `return(values[1, 1])`
- L5: `}`
- L6: `total <- 0L`
- L7: `for (j in seq_len(n)) {`
- L8: `term <- values[1, j] * laplace(values[-1, -j, drop = FALSE])`
- L9: `total <- total + if (j %% 2 == 1) term else -term`
- L10: `}`
- L11: `total`
- L14: `matrices <- list(`
- L15: `matrix(as.integer(c(2, -3, 1, 5, 4, -2, -1, 6, 3)), nrow = 3, byrow = TRUE),`
- L21: `)`

Minimization: The recursive routine and first-matrix literal are needed for the concrete first term. Other matrices can be omitted on separately written lines; the J literal necessarily shares its complete line with the other matrices. The selected complete original lines, in source order, cost 211 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 405, and the complete source costs 454. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
