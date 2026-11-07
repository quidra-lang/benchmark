# Task B selection — 91_priority_queue_tasks / JavaScript

Change the equal-priority comparison in less to the task names. Push and pop both compare via less, and the run and remaining loop both call pop. The command fixtures and print formats add no additional ordering logic.

Selected complete source lines: 2, 4, 9, 15, 22, 23, 40, 43, 44, 48.

With the benchmark tokenizer, this selection measures 254 tokens; the previous selection measured 224. The full source is 764 tokens.

## Current token measurement

Task A: **760 tokens**. Task B: **251 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
