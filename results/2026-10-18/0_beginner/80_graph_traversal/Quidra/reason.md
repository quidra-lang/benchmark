# Task B selection — 80_graph_traversal / Quidra

The edge list and adjacency builder establish the graph and its ascending neighbor order. DFS marks a vertex on entry and reaches 7 from 2. BFS marks vertices when enqueuing them and also discovers 7 from 2, but removes the previously queued 5 before visiting 7. Both traverse the component of 0. The final reset and scan start a DFS at each still-unvisited vertex, so the other component is included and each component is sorted independently. The queue and adjacency helper contracts establish FIFO removal and sorted neighbor lists without their implementations. Output formatting and component labels do not affect the trace.

Selected source lines in order are 1, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 32, 33, 34, 35, 36, 37, 38.

Task A uses 572 tokens. Task B uses 460 tokens.

Measurement: Task A 572; Task B 460. Tokenizer: metric/tokenizer.py, unchanged.
