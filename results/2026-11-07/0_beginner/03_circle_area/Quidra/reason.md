# Task B selection: 03_circle_area / Quidra

## Answer requirements

Locate the expression that formats the area field for radius 7. Explain which precision and literal label it uses and how it retains trailing fractional zeros. Focus on this one numeric-to-text expression; do not retrace the area calculation or the circumference field.

## Answer and source evidence

The area placeholder has the literal label `area=` and fixed three-place fractional presentation. Fixed precision retains zeros, including an area whose formatted fraction ends in zero. Radius 7 does not alter this formatter. The area computation and circumference are outside the question; they occur on the same physical output line and cannot be split out.



Selected `main.qui` lines: 5. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
