# Task B selection: 64_spiral_matrix / Quidra

## Answer requirements

Explain the rendering operation from the completed 5-by-6 numeric matrix to its five output lines. Identify row iteration order, integer conversion, three-character left padding, concatenation of six fields and newline emission. Show why each row has exactly 18 characters before the newline and why padding is output text rather than part of the stored matrix values. Do not retrace spiral construction.

## Answer and source evidence

Rows are visited in stored order, then each row's six integers is converted to decimal in a width-three field with leading spaces. Six concatenated fields give 18 characters before one newline. The padding is produced by formatting and never written back into numeric matrix storage. Python join("") creates no separators and print terminates once; Quidra print emits each field and println() terminates after the inner loop. Spiral construction is outside this question.



Selected `main.qui` lines: 1, 19, 20, 21, 22. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
