# Task B selection: 31_pascal_triangle / Quidra

## Answer requirements

Locate the block that constructs row 1 from row 0 and distinguish endpoint handling from interior addition. Explain how the single initial value and two row-1 endpoints are supplied, and identify the condition, range or construction that prevents reading nonexistent neighboring entries of the preceding row. Do not derive a whole later row.

## Answer and source evidence

The initial row is [1]. Python explicitly constructs [1] + an empty interior comprehension + [1], because range(1,1) has no index. Quidra pads the prior row to [0,1] and [1,0], then adds elementwise to [1,1]. Both supply two row-1 endpoints without accessing nonexistent prior neighbors; later iteration and printing are unrelated to this construction.



Selected `main.qui` lines: 3, 4, 7. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
