# Task B selection — 19_bmi_calculator / Quidra

Mika contributes height 165 and weight 70. The integer products are 700000 and 27225. Both are converted to real before division, giving an unrounded BMI of about 25.7117. The thresholds 18.5 and 25.0 do not match, and the threshold 30.0 does, so the category is overweight. Only the output interpolation applies half-up rounding to one fractional digit, displaying 25.7. The other fixture rows and the fallback category cannot affect Mika's result.

Selected complete source lines in order are 1, 4, 8, 9, 10, 11, 12, 13, 16.

Tokenizer: Task A 250 tokens; Task B 168 tokens.

Measurement: Task A 250; Task B 168. Tokenizer: metric/tokenizer.py, unchanged.

## Current token measurement

The tuple-array fixture types are inferred from the retained nonempty literal entries using Core numeric and string literal defaults; removing the redundant annotations does not remove a fact needed for this answer.

Task A: **239 tokens**. Task B: **157 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
