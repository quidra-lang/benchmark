# Task B selection — 91_priority_queue_tasks / Go

The container/heap contract takes its ordering from Less. Change the equal-priority return to compare name fields and keep numeric priority ascending. Both the run and remaining-task loop call heap.Pop on this same TaskQueue. The command fixtures and print formats add no additional ordering logic.

Selected complete source lines: 8, 9, 13, 17, 18, 19, 20, 21, 37, 43, 44, 54, 55.

With the benchmark tokenizer, this selection measures 181 tokens; the previous selection measured 155. The full source is 723 tokens.

## Current token measurement

Task A: **719 tokens**. Task B: **181 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
