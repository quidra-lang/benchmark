# Task B selection: 19_bmi_calculator / Kotlin

Mika’s height and weight are 165 and 70, giving integer products 700000 and 27225 and a real BMI of about 25.7117. It is at least 18.5 and 25 and below 30, so it is overweight. The numeric display is 25.7 with one decimal digit. This input is not a halfway case, so its result does not establish how the formatter breaks exact decimal ties.

The aligned arrays supply Mika’s measurements. toDouble changes the numerator before division; when uses unrounded bmi and %.1f in the output requests a single fractional digit.

Complete main.kt lines: 4, 5, 6, 8, 9, 10, 11, 12, 15. The unused classification result arms and punctuation do not affect the named trace; retain the ordered conditions, the matching label and the separate output operation. Other records are unnecessary except where they share a source line with Mika. The benchmark tokenizer counts 249 tokens in this excerpt.

## Current token measurement

Task A: **299 tokens**. Task B: **248 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
