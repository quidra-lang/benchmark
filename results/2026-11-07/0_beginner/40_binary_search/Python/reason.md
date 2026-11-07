# Task B selection: 40_binary_search / Python

## Answer requirements

Identify the first midpoint expression evaluated for target 42 and the array element read with its result. Explain why the recorded probe is a zero-based position rather than the element value or its one-based ordinal, citing the actual indexing and recording expressions. Stop before tracing later search steps.

## Answer and source evidence

The first midpoint is floor((0+15)/2)=7, and values[7]=31. The probe records or prints mid itself, not values[mid] and not mid+1, so 7 is a zero-based physical position rather than value 31 or ordinal 8. The target 42 is supplied in the question; later branch updates are unnecessary.



Selected `main.py` lines: 1, 3, 6, 7, 8. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
