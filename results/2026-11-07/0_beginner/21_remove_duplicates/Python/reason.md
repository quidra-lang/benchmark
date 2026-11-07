# Task B selection: 21_remove_duplicates / Python

## Answer requirements

Explain the complete run from the fifteen stored integers through duplicate detection, retained-value ordering and the two final output lines. Trace the three occurrences of 12 as a concrete example, then derive the retained sequence and removed count. Identify the source operations that distinguish a repeated value from a new value, preserve first appearance and construct each output line.

## Answer and source evidence

The retained sequence is `12 5 8 3 20 15 7 9`, and the second line is `removed: 7`. The first 12 creates the first retained entry; its next two occurrences find that value already present and do not append another. Stable deduplication preserves first appearance. Original length 15 minus unique length 8 gives seven removals. The selected input, stable unique operation, count difference and two-line construction cover the full requested run.

dict insertion order is a Python language guarantee; dict.fromkeys keeps the first insertion position.

Selected `main.py` lines: 1, 2, 3, 4. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
