# Task B selection — 83_topological_sort / Java

Keep names sorted for the ascending cycle traversal. Select the greatest eligible index instead of the first and retain the -1 fallback. The next choice still uses current eligibility, the empty selection still stops the loop, and the output format requires no edit. Graph construction and printing add no evidence about the selection change.

Selected complete source lines: 8, 9, 20, 34.

With the benchmark tokenizer, this selection measures 153 tokens; the previous selection measured 114. The full source is 979 tokens.

## Current token measurement

Task A: **975 tokens**. Task B: **150 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
