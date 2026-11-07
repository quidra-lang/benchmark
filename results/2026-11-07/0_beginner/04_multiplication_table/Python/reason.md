# Task B selection: 04_multiplication_table / Python

## Answer requirements

Suppose the table is expanded to 12 rows and 12 columns, with every product right-aligned in four characters. Explain how to coordinate the row/column iteration bounds with field formatting and row emission. Use the first and last products of row 12 to show why both dimensions and the field width must agree, and identify how twelve fields become exactly one line without separators or trailing whitespace.

## Answer and source evidence

Both dimensions currently enumerate 1 through 9. Change both inclusive endpoints to 12 (or each exclusive endpoint from 10 to 13) and each product field from width 3 to width 4. Row 12 starts with 12 and ends with 144. Each field is right aligned with leading spaces; concatenating twelve fields gives a 48-character row with no separators, and the line-writing operation terminates it once.

The generator feeds join("") inside one print; join introduces no separators.

Selected `main.py` lines: 1, 2. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
