# Task B selection: 08_leap_years / Python

## Answer requirements

Suppose 2400 is appended after 2100 in the input array. Explain the complete path from adding that data element through Gregorian divisibility tests to printing its result as the ninth line. Derive that line, including its lowercase label, and identify why the existing eight lines retain their original order and meaning. Ground the proposed change and the classification of 2400 in the actual source.

## Answer and source evidence

Append 2400 after 2100 in the literal sequence. Iteration retains input order, so it becomes the ninth element. The divisibility-by-400 branch is true, selecting lowercase `leap year`; output becomes `2400: leap year`. The eight prior values and the same classifier are unchanged, so their order and results remain the same.



Selected `main.py` lines: 1, 2, 3, 4, 5. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
