# Task B selection — 80_graph_traversal / Quidra

The edge tuples and symmetric adjacency assignments establish the undirected graph. Numeric neighbor loops examine neighbors in ascending order. DFS marks a vertex when entering its recursive call and appends it before descending; BFS marks a newly discovered neighbor before pushing it into the FIFO queue. Both first discover 7 through 2, but BFS visits 5 before removing 7, while DFS immediately descends through 7. The recursive call, queue processing and resets identify the two separately accumulated orders.

The final visited reset, scan of every vertex and recursive calls account for the component containing 1, 4 and 6 as well as the component reachable from 0. Sorting each completed component makes its recorded membership independent of DFS visit order. Collections imports establish the documented queue and mutable array extension contracts.

Display-helper implementation and final component formatting add no discovery, visitation or membership evidence, so they are omitted. Every selected line is copied verbatim from the source in order. The selection does not establish compilation or execution.
