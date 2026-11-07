# Task B selection: 99_expression_evaluator / Quidra

## Answer requirements

Explain evaluation of the single assignment height = 100 / (height - 7) + bonus, from token input and the existing variable table to its error result. Follow recursive-descent precedence and left-to-right evaluation far enough to identify the zero divisor and the guard that stops evaluation before a bonus lookup. Show where assignment is deferred so the previous height survives and how the error becomes the output line. Do not trace the other eight input lines.

## Answer and source evidence

Earlier width=12 and height=width-5 leave height7. Tokenization separates the assignment target from its expression. Recursive-descent expression calls product/term before addition; the denominator parenthesis recursively evaluates height-7 to0. Its division guard raises/returns `division by zero` before evaluating the later +bonus operand, so no undefined-bonus lookup occurs. Assignment commits only after successful expression evaluation; the existing height remains7. The failure branch writes `error: division by zero`. Selected precedence, variable read, zero guard, propagation, deferred write and error renderer support this one assignment; unrelated input statements are retained only when they share a physical source line.



Selected `main.qui` lines: 5, 6, 7, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 51, 52, 53, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
