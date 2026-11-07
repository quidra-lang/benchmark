# Task B selection — 91_priority_queue_tasks / Rust

BinaryHeap is a max heap and Reverse makes the lowest lexicographic tuple come out first. Put name after priority in the tuple and remove the insertion sequence; change both pop patterns to the revised tuple layout. The command fixtures and print formats add no additional ordering logic.

Selected complete source lines: 1, 2, 5, 26, 27, 31, 36.

With the benchmark tokenizer, this selection measures 140 tokens; the previous selection measured 106. The full source is 474 tokens.

## Current token measurement

Task A: **465 tokens**. Task B: **136 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
