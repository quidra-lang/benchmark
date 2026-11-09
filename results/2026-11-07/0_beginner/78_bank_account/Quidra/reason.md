# Task B selection: 78_bank_account / Quidra

## Answer requirements

For the first withdraw Leo 4000, locate the expression that constructs the failed-transaction line. Explain how it combines the existing operation number, unchanged transaction text and exact failed (insufficient funds) suffix with spaces and parentheses. Focus on this output representation; do not retrace account balances.

## Answer and source evidence

The formatter combines the existing operation number, colon and space, untouched transaction text, one separating space and the exact failed suffix, in the form `op N: withdraw Leo 4000 failed (insufficient funds)`. Parentheses belong to the literal status string. The question supplies failure and the transaction, so no balance trace is needed. Numbering/loop binding establishes which existing operation field is rendered.



Selected `main.qui` lines: 17, 31, 32. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
