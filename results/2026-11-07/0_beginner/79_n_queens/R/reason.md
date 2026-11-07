# Task B: 79_n_queens / R

Reverse the per-row candidate column traversal while retaining the same empty board state, column/diagonal rejection and full recursion/restoration. Descending traversal makes the first size-eight solution `[7,3,0,2,5,1,6,4]` in zero-based columns, the horizontal reflection of the ascending first solution. Retain its independent first-solution snapshot before later branches overwrite working positions, then render rows at those columns. Exhaustive counts remain N=4:2,5:10,6:4,7:40,8:92: candidate order changes discovery order, not which placements are examined.

Reverse the candidate sequence in solve. Working columns are replaced per depth; first is retained as an independent value result rather than a live mutable node structure.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L23,L24,L25,L26,L27.

- L1: `solve_queens <- function(n) {`
- L2: `columns <- rep(-1L, n)`
- L3: `first_solution <- integer(0)`
- L4: `solutions <- 0`
- L5: `place <- function(row) {`
- L6: `if (row == n) {`
- L7: `solutions <<- solutions + 1`
- L8: `if (length(first_solution) == 0) first_solution <<- columns`
- L9: `return(invisible(NULL))`
- L10: `}`
- L11: `previous <- seq_len(row)`
- L12: `for (column in 0:(n - 1)) {`
- L13: `if (all(columns[previous] != column & abs(columns[previous] - column) != row + 1 - previous)) {`
- L14: `columns[row + 1] <<- column`
- L15: `place(row + 1)`
- L16: `}`
- L17: `}`
- L18: `}`
- L19: `place(0)`
- L20: `list(count = solutions, first = first_solution)`
- L21: `}`
- L23: `for (n in 4:8) {`
- L24: `result <- solve_queens(n)`
- L25: `cat(sprintf("N=%d: %d solutions\n", n, result$count))`
- L26: `}`
- L27: `for (column in result$first) cat(strrep(".", column), "Q", strrep(".", 7 - column), "\n", sep = "")`

Minimization: The recursive enumerator, candidate validity, working-state restoration/overwrite, first snapshot, requested sizes and board rendering are needed for this complete ordering change. No unrelated source is selected. The selected complete original lines, in source order, cost 380 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 381, and the complete source costs 381. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
