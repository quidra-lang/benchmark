# Task B selection: 06_factorial_table / Quidra

## Answer requirements

Suppose the binding for the current factorial term number is renamed to term_number. In the loop or equivalent local block, identify its binding site and the references in the factorial calculation or call and the n! label that must follow the rename. Explain which literal text and any independently scoped callable parameter names do not need to change.

## Answer and source evidence

Rename the loop binding n and its references in the factorial operand/call and interpolated label to term_number. The literal exclamation mark, equals sign and spaces remain text. The name of an independently scoped factorial parameter is unaffected because it is not this loop binding.

Postfix ! directly applies factorial to the local binding; no helper parameter participates.

Selected `main.qui` lines: 1, 2. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
