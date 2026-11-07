# Task B selection: 52_polygon_area / Quidra

## Answer requirements

If an empty vertex sequence were substituted for polygon 1, follow the local initialization and edge-loop entry/exit block. Explain whether the last-to-first access would be evaluated or skipped, whether another access fails first, and which defaults would reach formatting if execution continues. Distinguish an explicit rejection, an implicit failure and a default result using the actual source rather than the nonempty-input promise.

## Answer and source evidence

An empty vertex sequence never enters its element iteration. Therefore the neighbor access, modulo by its length and last-to-first closure access are all skipped; there is no earlier vertex[0] access. Initial cross sum 0 and perimeter 0 reach formatting, producing area 0.0 and perimeter 0.000. This is a default empty result, not an explicit rejection or an implicit index failure. Arithmetic solely inside the skipped body adds no necessary evidence.



Selected `main.qui` lines: 9, 10, 11, 12, 17, 18, 19, 20. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
