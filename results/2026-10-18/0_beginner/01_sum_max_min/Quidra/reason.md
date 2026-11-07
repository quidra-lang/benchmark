# Task B selection — 01_sum_max_min / Quidra

The array contains −23 once and 5 twice. `sum()` visits every element, so −23 reduces the sum from 115 to 92 and the two occurrences of 5 contribute 10. `min()` compares element values and reports −23. A duplicate contributes another term to the sum but cannot change the minimum value.

The array declaration supplies the input elements. The `println(` line establishes that the labeled results are printed, and the `sum` and `min` lines identify the two Core calls. These are source lines 1–3 and 5. Line 4 supplies the separate maximum result, and line 6 closes the call.

`metric/tokenizer.py` counts 84 tokens in the complete program for Task A and 71 tokens in the four selected lines for Task B.

## Current token measurement

Task A: **81 tokens**. Task B: **69 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
