# Task B selection: 59_date_add_days / Python

## Answer requirements

Suppose each existing day count is subtracted instead of added and the displayed operator becomes a minus sign. Explain how backward day advancement must interact with month lengths and Gregorian leap-year handling at month/year boundaries, and how the resulting date is passed to the existing zero-padded formatter while the original date remains on the left. Use one boundary crossed during the 120-day case to make the dependency concrete; do not trace all 1500 days.

## Answer and source evidence

Replace forward advancement by decrementing day; when day becomes zero, move to the preceding month (or December of the preceding year) and choose that month's length using Gregorian leap-year rules for the destination year. In the 120-day case, stepping backward from 2023-11-01 crosses to 2023-10-31. Preserve original before mutation, pass the final year/month/day to the existing zero-padded formatter, and replace the displayed + by -. The number of iterations remains the requested day count; unrelated input cases are omitted.



Selected `main.py` lines: 1, 2, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
