# Task B selection: 42_triangle_classify / Quidra

## Answer requirements

Suppose equality a+b=c must be reported separately as degenerate, while a+b<c still reports not a triangle. Explain where and how to split the current validity-test block before side and angle classification. Show which supplied set reaches the equality branch and how valid triangles continue into the existing classification block. Leave all other boundaries unchanged.

## Answer and source evidence

After sorting the three sides, split the current a+b<=c condition into a+b<c yielding `not a triangle`, equality yielding `degenerate`, and the existing positive-area else path. The supplied (3,8,5) sorts to (3,5,8) and reaches equality. The side-equality and squared-angle comparisons stay in the strict-valid branch with their original boundaries. The selected first triple and ordered-value assignment establish the concrete equality case; unrelated input records and outer output prefixes are excluded.



Selected `main.qui` lines: 1, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
