# Task B selection: 43_run_length_encoding / Quidra

## Answer requirements

Trace the complete encoding/decoding path for the second string, with its runs of twelve W characters separated by B. Derive its encoded form and final decoded form, explain the maximal-run scan and two-digit count parsing, and show how the decoder uses encoded data instead of copying the original. Derive the full output line, including both arrows and spacing.

## Answer and source evidence

The second input has runs W*12,B*1,W*12,B*3, giving `12W1B12W3B`. Encoding groups maximal adjacent equal letters. Decoding consumes an entire decimal count, so 12 is not two separate runs, then repeats its following letter. The decoder receives encoded data and stores a new decoded result; it does not reuse the original string. The output is `WWWWWWWWWWWWBWWWWWWWWWWWWBBB -> 12W1B12W3B -> WWWWWWWWWWWWBWWWWWWWWWWWWBBB` with literal spaces around both arrows.

Cursor.take_nat consumes the complete number, take_char the following letter; result accumulates the expansion.

Selected `main.qui` lines: 3, 4, 5, 6, 7, 8, 9, 10, 14, 18, 19, 20, 21, 22, 23. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
