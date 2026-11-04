# Task B selection: 93_sudoku_solver / Quidra

## Common answer requirements

Reverse the digit candidate order while preserving first solution, placement counting, and backtracking.

## Source evidence

The digit loop currently tries 1 through 9. Reverse that loop to try 9 through 1, keeping the next-empty-cell search and validation logic. The retained placement operations count a successful write before recursion, propagate the first success without undoing it, and clear the cell after a failed recursive call. They should remain where they are.

## Minimization

The retained completion and placement lines establish how changing order affects the first solution and placement count. Conflict expressions and output formatting stay unchanged. Selected complete lines of `main.qui`: 4, 5, 6, 7, 8, 9, 10, 13, 24, 25, 26, 27, 28, 29.
