# Task B selection: 88_maze_shortest_path / Kotlin

Current parents are flattened integer cell numbers r*13+c, with -1 for unseen and start pointing to itself. Store row/column pairs uniformly at discovery and initialize a matching pair-valued start marker; update unseen tests and reconstruction to read pairs and index by the corresponding cell. Queue/discovery order need not change. The source does not already use pair parents.

Keep encoding, parent type/default/start, first-write/unseen check and reconstruction read/indexing. Maze literals, unrelated BFS bounds and final rendering do not affect the representation agreement.

Selected complete source lines in `main.kt`: 18, 22, 23, 29, 30, 31, 37, 38, 39, 40, 45, 46, 47, 48, 49. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
