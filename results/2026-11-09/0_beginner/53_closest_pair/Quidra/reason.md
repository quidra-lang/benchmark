# Task B selection: 53_closest_pair / Quidra

## Answer requirements

Suppose both pair results must print squared distance as a decimal integer instead of Euclidean distance with four fractional digits. Explain how selection by squared distance connects to the later square-root/formatting stage and where to change only the reported quantity. Identify why closest/farthest pair selection and its tie-break stay the same, and how the new integer field fits the existing two output lines.

## Answer and source evidence

Pair comparisons already use squared distances; retain those comparisons and their strict improvement conditions, which keep the first pair on ties in lexicographic iteration order. Change only the report stage to use the saved squared integer instead of applying sqrt and a four-place floating formatter. Keep both closest/farthest labels and point indices. The two result lines then contain decimal integer squared distances. Coordinate values and difference calculations do not affect where this reporting-only change belongs.



Selected `main.qui` lines: 13, 14, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
