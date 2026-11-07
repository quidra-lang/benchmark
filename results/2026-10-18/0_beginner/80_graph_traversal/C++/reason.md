# Task B selection — 80_graph_traversal / C++

Ascending neighbors give DFS 0, 2, 7, 5, 3, 8. DFS first enters 7 from 2 and marks it before exploring its neighbors. In BFS, 0 enqueues 2 and 5, then processing 2 marks 7 and appends it behind 5, giving 0, 2, 5, 7, 3, 8. The queue loop prints the dequeued vertex directly, so its body line establishes the emitted order. Both cover the same component; the independent reset and all-vertex scan then reach 1, 4 and 6. Each component is sorted separately, making its presentation independent of the traversal order.

Selected complete source lines: 6, 7, 8, 9, 10, 11, 12, 13, 16, 17, 18, 19, 20, 21, 22, 27, 28, 29, 31, 32, 33, 34, 35, 36, 37, 38, 39, 41, 42, 43, 44, 45, 46, 47, 48.

With the benchmark tokenizer, this selection measures 680 tokens; the previous selection measured 663. The full source is 949 tokens.

## Current token measurement

Task A: **941 tokens**. Task B: **675 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
