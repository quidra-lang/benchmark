# Task B selection: 14_moving_average / Python

## Answer requirements

Suppose the moving-average operation accepts a positive window size w: it must use complete windows only and print no complete window once if w exceeds the ten-day input length. Explain how to adapt the current operation from its input sales and w through window bounds, sum, real-number division and formatted day result. Use w=5 to establish the six valid day labels and w=11 for the missing-window path. Identify the source sites that must agree; do not add behavior for nonpositive w.

## Answer and source evidence

Replace the named window value with the positive argument w, coordinating the start/end bounds, window slice and real mean divisor. For w=5, complete windows end on days 5 through 10, producing six labels. For w=11, take an early path that prints `no complete window` once and skips all averages. Keep two-place presentation; the complete-window count is length-w+1 when positive.

The Python slice is half open: sales[day-window:day] contains window elements. `/ window` retains a real result.

Selected `main.py` lines: 1, 2, 3, 4, 5. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
