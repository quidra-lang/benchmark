# Task B selection — 80_graph_traversal / Julia

Ascending neighbors give DFS 0, 2, 7, 5, 3, 8. DFS first enters 7 from 2 and marks it before exploring its neighbors. In BFS, 0 enqueues 2 and 5, then processing 2 marks 7 and appends it behind 5, giving 0, 2, 5, 7, 3, 8. The BFS print joins the whole queue in append order; the head index advances in the same order. Both cover the same component; the independent reset and all-vertex scan then reach 1, 4 and 6. Each component is sorted separately, making its presentation independent of the traversal order.

Selected complete source lines: 1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39.

With the benchmark tokenizer, this selection measures 501 tokens; the previous selection measured 480. The full source is 609 tokens.

## Current token measurement

Task A: **607 tokens**. Task B: **501 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
