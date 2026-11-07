# Task B selection: 82_rpn_calculator / Quidra

## Answer requirements

Explain the RPN-expression evaluation operation from tokens to one result or an error. Use expression 2 to trace pushes, the two-operand pop order, result pushes and truncating negative division. Identify the entry/reset state and the guards for underflow, zero divisor and leftover operands, showing how an error stops further stack updates. Ground the behavior in the source's actual storage changes; do not trace all seven expressions.

## Answer and source evidence

Expression2 pushes -17,5, then / pops b=5 followed by a=-17 and pushes trunc(-17/5)=-3. It pushes4,-3, multiplies to -12, then subtracts -3-(-12)=9. Each expression begins with a fresh empty stack and no error. Underflow is checked before two pops; a zero divisor stops before a result push; after tokens, a successful stack must hold exactly one operand or becomes a leftover-operands error. Breaks prevent later token updates on failure. The selected branches cover this result and all asked error guards, not other complete expressions.



Selected `main.qui` lines: 3, 5, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
