# Task B selection: 38_insertion_sort_steps / Quidra

## Answer requirements

At insertion step i=1, locate the operation that increments the per-step shift count. Explain why one existing array value moved right counts once while the final write of the extracted value does not add another shift. Focus on this count update and its unit, rather than tracing the sort or all assignments.

## Answer and source evidence

The shift counter increments inside the loop that copies an existing entry into its right neighbor. At step i=1 that loop moves the existing value once; its one shifts+=1 counts one rightward copy. The final placement of the extracted value lies after the loop and has no counter increment, so it is not another shift. Initial inputs, cumulative totals and printing are outside this single-update question.



Selected `main.qui` lines: 9, 10, 11, 12, 13. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
