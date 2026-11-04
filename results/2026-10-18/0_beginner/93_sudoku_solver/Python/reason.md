# Task B selection: 93_sudoku_solver / Python

## Common answer requirements

Reverse the digit candidate order while preserving first solution, placement counting, and backtracking.

## Source evidence

The digit loop currently tries 1 through 9. Reverse that loop to try 9 through 1, keeping the next-empty-cell search and validation logic. The retained placement operations count a successful write before recursion, propagate the first success without undoing it, and clear the cell after a failed recursive call. They should remain where they are.

## Minimization

The retained completion and placement lines establish how changing order affects the first solution and placement count. Conflict expressions and output formatting stay unchanged. Selected complete lines of `main.py`: 9, 16, 17, 18, 19, 20, 21, 22, 34, 35, 36, 37, 38, 39, 40.
