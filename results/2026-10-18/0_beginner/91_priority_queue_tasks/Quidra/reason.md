# Task B selection — 91_priority_queue_tasks / Quidra

The queue key is numeric and the task name is its value. Pass a strict ascending name comparison as tie_before to the PriorityQueue constructor. The documented option only changes equal-priority order, and the same queue take is used for runs and for the final drain. The command fixtures and print formats add no additional ordering logic.

Selected complete source lines: 1, 8, 12, 14, 15, 17, 18, 19.

With the benchmark tokenizer, this selection measures 115 tokens; the previous selection measured 118. The full source is 315 tokens.

Measurement: Task A 315; Task B 115. Tokenizer: metric/tokenizer.py, unchanged.

## Current token measurement

Task A: **311 tokens**. Task B: **111 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
