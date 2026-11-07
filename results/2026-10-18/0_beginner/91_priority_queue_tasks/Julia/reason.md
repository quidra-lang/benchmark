# Task B selection — 91_priority_queue_tasks / Julia

isless orders the tuple lexicographically. Change its key from priority, sequence, name to priority, name; update the tuple element type, the run unpack and the final name index accordingly. Heap comparison stays in place and applies to both pop call sites. The command fixtures and print formats add no additional ordering logic.

Selected complete source lines: 1, 6, 12, 20, 23, 50, 54, 56, 57, 62.

With the benchmark tokenizer, this selection measures 222 tokens; the previous selection measured 168. The full source is 716 tokens.

## Current token measurement

Task A: **714 tokens**. Task B: **222 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
