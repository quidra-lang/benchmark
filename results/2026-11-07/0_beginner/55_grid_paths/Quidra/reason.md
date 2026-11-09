# Task B selection: 55_grid_paths / Quidra

## Answer requirements

Locate the initialization that gives the top-left grid cell its starting path count. Explain why the value is one empty route rather than zero and how the actual source establishes it in both counting cases. Focus on this base-state expression rather than propagating the grid recurrence.

## Answer and source evidence

The top-left path count is explicitly initialized to 1, representing the single empty route before taking any grid step. Both no-obstacle and obstacle calls enter the same routine and execute that initialization; the grid starts unblocked. No recurrence propagation is required to identify this base state. The selected calls show that both modes share this base-state operation.



Selected `main.qui` lines: 4, 13. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
