# Task B selection: 41_quadratic_roots / Python

## Answer requirements

For coefficients (-2, 5, 4), follow the local block from the integer discriminant to the two unformatted real-root candidates. Identify the square root, negative denominator and division operations, explaining which values are integer-valued and which must retain fractions. Distinguish the actual declarations/conversions or runtime operation semantics from mathematical requirements, and identify how the candidates are ordered before formatting.

## Answer and source evidence

For a=-2,b=5,c=4 the exact integer discriminant is 57 and denominator 2a=-4. The candidates are (-5+sqrt(57))/-4 and (-5-sqrt(57))/-4; the second is the larger one because the denominator is negative. The ordering stage chooses the larger candidate for x1 and smaller for x2 before text formatting. The square root and subsequent divisions must retain fractions.

math.sqrt returns float and `/` uses real-number division; the discriminant remains a runtime int without a static type declaration. max/min on roots provide the order; their physical source line also contains output precision.

Selected `main.py` lines: 11, 12, 13, 14, 15, 16, 17. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
