# Task B selection: 57_matrix_determinant / Quidra

## Answer requirements

Explain the determinant operation from an input matrix to its returned signed integer. Identify the one-entry base case, minor construction, recursive call and alternating signed accumulation, using the first expansion term of matrix 1 as a concrete example. Explain whether this source introduces any real-number division or rounding before output and how exact signed terms are retained. Do not expand all three determinants by hand.

## Answer and source evidence

A one-entry matrix returns that signed integer. Otherwise expand the first row: remove its row and the current column to create a minor, recursively compute its determinant, multiply by the current entry and alternate plus/minus with column parity. Matrix 1 first term is +2*det([[4,-2],[6,3]])=2*(12+12)=48. No division or rounding appears in this operation; additions/subtractions/multiplications retain exact signed integer terms.

The argument/return type int and inferred total/term provide an exact arbitrary-precision integer contract.

Selected `main.qui` lines: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
