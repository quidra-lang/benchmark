# Task B selection: 56_permutations / Quidra

## Answer requirements

Explain the complete recursive enumeration from an empty partial permutation and unused ABCD characters to the twenty-four numbered lines. Trace the first completed permutation and the return path from the last A-starting permutation to the first B-starting permutation. Identify how choices are restored, completed permutations receive sequence numbers, and the search exhausts all branches without duplicates. Derive the first and last lines and total line count from the source.

## Answer and source evidence

Depth-first choices in ABCD order yield first `1: ABCD` and last `24: DCBA`, with 4!=24 complete permutations. Completion increments the count once and returns before extending further. After the last A-starting permutation ADCB returns, choices unwind through all A-prefixed branches, restoring availability, then B is selected at the root and the next completion is BACD. Each character is used once per branch, giving no duplicates.

Each recursive prefix is a value and membership excludes already chosen letters; returning the updated count carries sequence numbering through sibling branches without shared mutation.

Selected `main.qui` lines: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
