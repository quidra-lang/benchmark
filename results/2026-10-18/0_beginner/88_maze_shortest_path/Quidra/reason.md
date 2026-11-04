# Task B selection — 88_maze_shortest_path / Quidra

The discovery guard writes a predecessor only for a cell that has no recorded parent. When that candidate is G, its parent is the currently expanded cell, and G is queued. The outer search loop exits after the expansion in which G gains a parent. Starting at G and repeatedly reading the recorded predecessor until S gives exactly the cells on that route in reverse. The backward walk increments the move counter once per parent link. A route with N cells has N−1 links and therefore N−1 moves. The walk stops before S and changes only cells that contain a period, so G and the walls retain their original characters. The final output uses the updated maze.

The retained candidate index uses the same flattened representation as the predecessor lookup. The omitted direction, bounds and coordinate-construction statements only determine how candidates are generated before their first-discovery guard. The larger previous selection measured 451 tokens before this source update; the current selected excerpt measures 309 tokens.

Selected complete source lines: 1, 2, 16, 17, 18, 19, 20, 22, 23, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 579; Task B 309.

Measurement: Task A 579; Task B 309. Tokenizer: metric/tokenizer.py, unchanged.
