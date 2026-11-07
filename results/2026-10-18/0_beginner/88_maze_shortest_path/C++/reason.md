# Task B selection — 88_maze_shortest_path / C++

The discovery guard writes a predecessor only for a cell that has no recorded parent. When that candidate is G, its parent is the currently expanded cell, and G is queued. The search continues until its FIFO queue is exhausted. Starting at G and repeatedly reading the recorded predecessor until S gives exactly the cells on that route in reverse. The start has distance zero, and the first-discovery update gives the child its parent’s distance plus one. Printing the goal distance counts parent links. A route with N cells has N−1 links and therefore N−1 moves. The walk stops before S and changes only cells that contain a period, so G and the walls retain their original characters. The final output uses the updated maze.

The retained candidate index uses the same flattened representation as the predecessor lookup. The omitted direction, bounds and coordinate-construction statements only determine how candidates are generated before their first-discovery guard. Including them as in the previous selection would cost 658 tokens instead of 490.

Selected complete source lines: 9, 10, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 27, 28, 29, 30, 31, 32, 34, 35, 36, 37, 38, 39, 40.

## Current token measurement

Task A: **834 tokens**. Task B: **489 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
