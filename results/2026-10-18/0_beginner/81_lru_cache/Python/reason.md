# Task B selection — 81_lru_cache / Python

The full-miss test is the only hard-coded capacity. Change the length comparison to four. The tail pop and front insertion already use relative positions and do not need separate evidence to locate the edit. Hit refresh, access sequence, counts, and output do not require edits. Including those paths adds no further capacity dependency.

Selected complete source lines: 11.

With the benchmark tokenizer, this selection measures 14 tokens; the previous selection measured 70. The full source is 252 tokens.

## Current token measurement

Task A: **251 tokens**. Task B: **14 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
