# Task B selection: 16_collatz_steps / Quidra

## Answer requirements

Suppose only the two result fields are reordered to n: max=M steps=K. Identify where and how the single output-format expression must change, including spaces and the lack of spaces around equals signs. Show which existing values supply M and K; leave their calculations unchanged.

## Answer and source evidence

Change the one output expression to put the existing maximum/largest field before steps, yielding `start: max=M steps=K`. Preserve one space after the colon and between fields, and no spaces around equals signs. M comes from maximum in Python or largest in Quidra; K comes from steps. Their calculations need no change.



Selected `main.qui` lines: 8. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
