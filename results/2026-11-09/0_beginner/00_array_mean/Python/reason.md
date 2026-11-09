# Task B selection: 00_array_mean / Python

## Answer requirements

Follow the small output-producing block from the unformatted mean to its completed line. Identify the numeric-to-text conversion, the precision or rounding operation, and the line-writing operation in the actual source. Explain how they jointly provide two fractional digits, retain a trailing zero when needed, and avoid an extra separator or trailing space. Distinguish formatting from the numeric value before formatting.

## Answer and source evidence

The named mean remains numeric until the output expression converts it to fixed-point text with two fractional digits. The line-writing call emits exactly that field and one newline; there is no extra argument or literal space. A trailing fractional zero is retained by the fixed precision.

The f-string .2f presentation rounds for display; `/` retains a fractional result before presentation.

Selected `main.py` lines: 2, 3. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
