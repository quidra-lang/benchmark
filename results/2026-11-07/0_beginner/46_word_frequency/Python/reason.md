# Task B selection: 46_word_frequency / Python

## Answer requirements

Locate the count-update operation used for the first and second occurrences of cat after normalization. Explain how an absent entry gets its initial count and how the same entry then increases, including any library default. Focus on this local update and whether it mutates storage or replaces a value; do not derive the ranking.

## Answer and source evidence

After normalization the first cat starts from the frequency aggregator default zero and contributes one; the next cat increments that same key from 1 to 2. Counts are keyed by the normalized word. Python Counter fills mutable count storage during construction; Quidra frequencies returns the accumulated map value. The caller binding receives the completed counts rather than changing the original text/token sequence. Ranking and the complete passage add no required fact about this local count update.



Selected `main.py` lines: 2, 5. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
