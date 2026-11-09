# Task B selection: 93_sudoku_solver / Quidra

## Answer requirements

Suppose the final count is reported in thousands of placements as placements (thousands): x.xxx, for example 1234 as 1.234. Follow the local reporting block from the exact counter through unit conversion, numeric-to-text formatting and line emission. Identify where and how to avoid integer-division truncation while retaining the original counter, and explain why exactly three fractional digits require no rounding of the count.

## Answer and source evidence

Change only the final report to the label `placements (thousands): ` and a decimal count divided by1000, keeping the original integer counter. An integer count has exactly three decimal subunit places in thousands, so no count rounding is needed. In Python, exact formatting can use quotient placements//1000 and remainder placements%1000 padded to three digits, avoiding both truncation and float precision loss. In Quidra use real(placements)/1000 with .3 fixed fractional precision; int/int division would truncate. The solver does not need to change.



Selected `main.qui` lines: 50. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
