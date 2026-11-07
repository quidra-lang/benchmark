# Task B selection: 19_bmi_calculator / Go

Mika’s height and weight are 165 and 70, giving integer products 700000 and 27225 and a real BMI of about 25.7117. It is at least 18.5 and 25 and below 30, so it is overweight. The numeric display is 25.7 with one decimal digit. This input is not a halfway case, so its result does not establish how the formatter breaks exact decimal ties.

The struct binds the tuple values to height and weight, the products are integer, and both are converted for the division. The first two comparisons fail and the third assigns overweight; %.1f is separate from those comparisons.

Complete main.go lines: 6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 19, 21. The unused classification result arms and punctuation do not affect the named trace; retain the ordered conditions, the matching label and the separate output operation. Other records are unnecessary except where they share a source line with Mika. The benchmark tokenizer counts 267 tokens in this excerpt.

## Current token measurement

Task A: **327 tokens**. Task B: **267 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
