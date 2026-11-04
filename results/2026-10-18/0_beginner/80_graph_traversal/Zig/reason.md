# Task B selection — 80_graph_traversal / Zig

Ascending neighbors give DFS 0, 2, 7, 5, 3, 8. DFS first enters 7 from 2 and marks it before exploring its neighbors. In BFS, 0 enqueues 2 and 5, then processing 2 marks 7 and appends it behind 5, giving 0, 2, 5, 7, 3, 8. The queue loop prints the dequeued vertex directly. The component sorting slice uses len directly, so saving that length for later formatting adds no evidence about membership. Both cover the same component; the independent reset and all-vertex scan then reach 1, 4 and 6. Each component is sorted separately, making its presentation independent of the traversal order.

Selected complete source lines: 3, 4, 5, 6, 7, 8, 9, 10, 11, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 28, 29, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 55, 56, 57, 58, 59, 61, 62.

With the benchmark tokenizer, this selection measures 777 tokens; the previous selection measured 767. The full source is 1170 tokens.
