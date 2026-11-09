Undirected insertion followed by sorted neighbors gives DFS "0 2 7 5 3 8" and BFS "0 2 5 7 3 8". DFS first reaches 7 recursively from 2; BFS first enqueues 7 while processing 2. Ascending component roots also discover {1,4,6}; there are two sorted component lines: "component 1: 0 2 3 5 7 8" and "component 2: 1 4 6".

DFS marks on entry and recurses immediately; BFS marks before enqueue and shifts a FIFO queue. Separate seen resets prevent traversal state leaking into component discovery; component.sort and i+1 define output.

Edges, bidirectional insertion, sorted neighbor traversal, DFS/BFS state and component-root order establish both walks and components. Unrelated graph algorithms are not involved.
