# Task B selection — 83_topological_sort / Rust

The filter limits the candidates to untaken courses with zero indegree. Change min_by_key to max_by_key on the same names without modifying which courses qualify. Both operations return no value on an empty candidate set, so termination is preserved. The cycle list has its own sort, so the order change has no shared sorting dependency.

Selected complete source lines: 15, 16.

With the benchmark tokenizer, this selection measures 51 tokens; the previous selection measured 22. The full source is 941 tokens.

## Current token measurement

Task A: **932 tokens**. Task B: **51 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
