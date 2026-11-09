# Task B selection: 80_graph_traversal / C#

Undirected symmetric adjacency and increasing vertex scans establish sorted-neighbor order. DFS first reaches 7 via 0,2,7; BFS discovers 7 from 2 after 0 enqueues 2 and 5. Orders are DFS: 0 2 7 5 3 8 and BFS: 0 2 5 7 3 8. Resetting visited and scanning all vertices finds component 1: 0 2 3 5 7 8 and component 2: 1 4 6; component members are sorted before numbered emission.

Every adjacency/traversal/component/output stage is required for the exact reports. Imports, top-level wrappers and unrelated culture setup are omitted; no library traversal implementation is assumed.

Selected complete source lines in `Program.cs`: 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
