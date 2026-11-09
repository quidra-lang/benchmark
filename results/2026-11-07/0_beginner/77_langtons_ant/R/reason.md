# Task B: 77_langtons_ant / R

Keep the current turn from cell color and the current cell flip before deciding movement. Compute proposed coordinates from the resulting direction, then commit both only if they lie within the board; otherwise retain both current coordinates. Replace the modulo wrapping at the move expressions with that bounds/commit step. A proposed upward move from row 0 to row -1 is refused, while the already completed turn and flip remain in effect.

Logical row/column are zero-based; the matrix access adds 1. Replace both %%11 movement assignments after the turn/flip with a shared bounds test.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11.

- L1: `board <- matrix(FALSE, 11, 11)`
- L2: `row <- 5`
- L3: `column <- 5`
- L4: `direction <- 0`
- L5: `directions <- list(c(-1, 0), c(0, 1), c(1, 0), c(0, -1))`
- L6: `for (step in 1:300) {`
- L7: `turn <- if (board[row + 1, column + 1]) -1 else 1`
- L8: `direction <- (direction + turn) %% 4`
- L9: `board[row + 1, column + 1] <- !board[row + 1, column + 1]`
- L10: `row <- (row + directions[[direction + 1]][1]) %% 11`
- L11: `column <- (column + directions[[direction + 1]][2]) %% 11`

Minimization: Incoming board/position/direction, color rule, flip, direction offsets and both coordinate updates are necessary for one complete step. Multi-step output is unrelated to boundary commit behavior. The selected complete original lines, in source order, cost 236 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 236, and the complete source costs 363. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
