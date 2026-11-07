# Task B selection — 80_graph_traversal / Quidra

The edge list and adjacency builder establish the graph and its ascending neighbor order. DFS marks a vertex on entry and reaches 7 from 2. BFS marks vertices when enqueuing them and also discovers 7 from 2, but removes the previously queued 5 before visiting 7. Both traverse the component of 0. The final reset and scan start a DFS at each still-unvisited vertex, so the other component is included and each component is sorted independently. The queue and adjacency helper contracts establish FIFO removal and sorted neighbor lists without their implementations. Output formatting and component labels do not affect the trace.

Selected source lines in order are 1, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 32, 33, 34, 35, 36, 37, 38.

Task A uses 569 tokens. Task B uses 457 tokens.

Measurement: Task A 569; Task B 457. Tokenizer: metric/tokenizer.py, unchanged.

The Queue<int> contract determines the removed vertex as int. The inferred binding preserves the same success type and failure handling.

## Current token measurement

The tuple-array fixture types are inferred from the retained nonempty literal entries using Core numeric and string literal defaults; removing the redundant annotations does not remove a fact needed for this answer.

Task A: **555 tokens**. Task B: **446 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
