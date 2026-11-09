# Task B selection: 79_n_queens / Python

## Answer requirements

Suppose columns are tried in decreasing order in every row for each board size. Explain the complete size-eight search path from initialization through candidate ordering, row/column/diagonal rejection, recursive restoration, first-solution retention and rendering, and identify where the descending order is introduced. Derive the new first size-eight solution and explain why exhaustive solution counts for all requested sizes remain unchanged despite different discovery order.

## Answer and source evidence

Introduce descending column enumeration in the recursive candidate loop at every row, leaving rejection and exhaustive traversal unchanged. For size8 the first placement becomes zero-based [7,3,0,2,5,1,6,4], the mirror of the ascending first placement. Completion retains its first solution once and increments the solution count; each failed/returned branch restores or passes independent placement state. Every original candidate still appears exactly once, so counts for sizes4..8 remain unchanged. The renderer puts Q at each retained column and dots elsewhere.

placement.append/pop restores the mutable search path, while placement.copy retains the first completed solution independently.

Selected `main.py` lines: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 28, 29, 30, 31, 32, 33, 34, 35. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
