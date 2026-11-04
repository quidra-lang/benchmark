# Task B selection — 88_maze_shortest_path / JavaScript

The discovery guard writes a predecessor only for a cell that has no recorded parent. When that candidate is G, its parent is the currently expanded cell, and G is queued. The search stops when G is removed from the queue. Starting at G and repeatedly reading the recorded predecessor until S gives exactly the cells on that route in reverse. The backward walk increments the move counter once per parent link. A route with N cells has N−1 links and therefore N−1 moves. The walk stops before S and changes only cells that contain a period, so G and the walls retain their original characters. The final output uses the updated maze.

The retained candidate index uses the same flattened representation as the predecessor lookup. The omitted direction, bounds and coordinate-construction statements only determine how candidates are generated before their first-discovery guard. Including them as in the previous selection would cost 521 tokens instead of 372.

Selected complete source lines: 5, 7, 8, 9, 10, 11, 12, 17, 18, 19, 20, 21, 24, 25, 26, 27, 28, 29, 30, 31, 32.
