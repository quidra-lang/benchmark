# Task B selection — 83_topological_sort / Python

The ready list is initially sorted and re-sorted after new candidates are added, so pop its tail rather than its head. Altering both sorts would require more edits; keep eligibility updates, exhaustion and the separate cycle sort. The next choice still uses current eligibility, the empty selection still stops the loop, and the output format requires no edit. Graph construction and printing add no evidence about the selection change.

Selected complete source lines: 7, 10, 16.

With the benchmark tokenizer, this selection measures 50 tokens; the previous selection measured 137. The full source is 615 tokens.

## Current token measurement

Task A: **614 tokens**. Task B: **49 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
