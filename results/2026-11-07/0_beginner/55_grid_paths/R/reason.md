# Task B: 55_grid_paths / R

The top-left base state is one path: the empty route already at the start, not a movement from a predecessor. Both counting cases invoke the same routine with different obstacle flags, so the same origin initialization applies. The supplied top-left cell is open, hence obstacle handling does not erase this one.

The origin condition assigns 1 in the shared counting routine after obstacle handling; both calls receive the same open top-left grid.

Evidence is from `main.R`, L1,L3,L4,L5,L6,L7,L8,L9,L19.

- L1: `grid <- c(".......", "..#....", "....#..", ".#.....", "...#.#.", ".......")`
- L3: `count_paths <- function(obstacles) {`
- L4: `paths <- matrix(0L, nrow = length(grid), ncol = nchar(grid[1]))`
- L5: `for (row in seq_len(nrow(paths))) {`
- L6: `for (column in seq_len(ncol(paths))) {`
- L7: `if (obstacles && substr(grid[row], column, column) == "#") next`
- L8: `if (row == 1 && column == 1) {`
- L9: `paths[row, column] <- 1L`
- L19: `cat(sprintf("without obstacles: %d\nwith obstacles: %d\n", count_paths(FALSE), count_paths(TRUE)))`

Minimization: The base/default state, origin-versus-obstacle condition and the two call modes are sufficient. The predecessor recurrence and propagation to the far corner are outside this base-state question. The selected complete original lines, in source order, cost 250 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 362, and the complete source costs 362. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
