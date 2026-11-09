# Task B selection: 77_langtons_ant / Quidra

## Answer requirements

Suppose an attempted move outside the board leaves the ant in its current cell after turning and flipping that cell, instead of wrapping. Explain how to adapt one complete ant-step operation from its incoming row/column/direction and color to its next state: turn, color inversion, proposed coordinate, bounds test and committed position. Use an attempted upward move from row 0 as a boundary example, preserving the turn/flip effects even when movement is refused.

## Answer and source evidence

Keep turn based on the current cell color and invert that cell before deciding movement. Compute proposed row/column without modulo, test both against the board bounds, and commit both only if in range; otherwise retain the incoming position. An upward attempt from row0 proposes -1 and is rejected, but its new direction and flipped cell remain. Replace the existing wrap expressions, preserving their dependency on the already updated direction. The original state and rendering are outside the one-step operation.



Selected `main.qui` lines: 5, 6, 8, 9, 10, 11. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
