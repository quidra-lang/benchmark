# Task B selection: 37_bubble_sort_passes / Quidra

## Answer requirements

Trace the complete sort of the supplied eight-element array through its passes to termination and final swap total. Explain comparison bounds, swaps, the per-pass no-swap indication and when each pass line is emitted. Use the movement of 88 in the first pass as a concrete check, then derive the final sorted array, the last printed pass number and total swaps from those source operations.

## Answer and source evidence

Comparisons use adjacent pairs only within the unsorted prefix; an inversion swaps once and increments both the cumulative counter and per-pass changed indication. In pass 1, 88 moves right successively past 41,5,72,36 to the final position. The sorted result is `5 13 27 36 41 64 72 88`. Five passes move 5 to the front; pass 6 performs no swaps but is printed before the changed test exits. The swap total is 14 (the input inversion count). Each pass resets changed before comparisons. All selected lines belong to the asked full sort; the import alone adds no algorithmic evidence.



Selected `main.qui` lines: 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
