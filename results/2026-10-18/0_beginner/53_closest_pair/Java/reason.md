# Task B selection: 53_closest_pair / Java

## Common answer requirements

Print the two stored squared distances as decimal integers, preserving pair selection, tie handling, labels, and layout.

## Source evidence

The squared-distance expression and the selected-pair updates show that the score stored for each extreme is already the value to print. The strict improvement tests preserve the earlier encounter when scores tie. Remove the square root/conversion at the output path and use ordinary decimal integer formatting instead of floating-point precision formatting. Preserve labels, point-name formatting and line order.

## Minimization

Print-only evidence would not establish that the value supplied to the square root is the squared value used by the comparisons. The strict comparisons and score stores suffice without the point literals or a trace of all pairs.

Selected complete lines of `Main.java`: 8, 11–14, 18–19, 25–26. The prior excerpt measured 250 tokens; this excerpt measures 282 with `metric/tokenizer.py`.
