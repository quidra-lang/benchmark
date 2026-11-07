# Task B selection: 18_number_with_commas / Python

## Answer requirements

Trace the complete formatting path for -456789, starting at its stored input value and ending at the printed line. Explain sign detection, extraction or traversal of magnitude digits, grouping from the right in threes, comma placement and reattachment of the minus sign. Derive the output line and identify why no comma can occur immediately after the sign or at the end.

## Answer and source evidence

The loop supplies -456789. The named negative decision is true, its magnitude is 456789, and sign is `-`. Formatting only the magnitude groups its digits from the right into 456 and 789 with one comma; reattaching sign produces `-456,789`. The sign is outside digit grouping, so no comma follows it, and the built-in grouping formatter puts commas only between nonempty groups, never at the end.



Selected `main.py` lines: 1, 2, 3, 4, 5. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
