# Task B selection: 62_edit_distance / Quidra

## Answer requirements

For the matching i characters at prefix lengths 2 and 2 in kitten and sitting, follow the local DP-cell update. Identify the equality decision, zero replacement cost, neighboring-prefix candidates and final minimum. Explain whether a character match skips evaluation of other alternatives or only changes which computed candidate wins, using the actual conditional/expression evaluation in the source.

## Answer and source evidence

At prefix lengths i=j=2, a[1] and b[1] are both i. The replacement cost is zero; deletion and insertion candidates still add 1 to their neighboring prefix entries, while the diagonal adds 0. For kitten/sitting these candidates are 3,3,1 and the minimum is 1. A character match changes cost, not control flow around min: all three arguments/array elements are evaluated before selecting the minimum. The question supplies the strings and cell, so other pairs and the full DP construction are unnecessary.



Selected `main.qui` lines: 9, 10, 11, 12, 13, 14, 15, 16. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
