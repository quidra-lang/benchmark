# Task B selection — 91_priority_queue_tasks / Lua

Change the sequence comparison in before to ascending name for equal priorities. Both heap operations already use before and both output paths remove via the same pop. The command fixtures and print formats add no additional ordering logic.

Selected complete source lines: 1, 2, 7, 12, 18, 26, 27, 44, 46, 47, 51.

With the benchmark tokenizer, this selection measures 285 tokens; the previous selection measured 246. The full source is 788 tokens.

## Current token measurement

Task A: **785 tokens**. Task B: **282 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
