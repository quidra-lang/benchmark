# Task B selection — 88_maze_shortest_path / R

A visited flag is set when the parent coordinates are first assigned. When that candidate is G, its parent is the currently expanded cell, and G is queued. The search stops when G is removed from the queue. Starting at G and repeatedly reading the recorded predecessor until S gives exactly the cells on that route in reverse. The backward walk increments the move counter once per parent link. A route with N cells has N−1 links and therefore N−1 moves. The walk stops before S and changes only cells that contain a period, so G and the walls retain their original characters. The final output uses the updated maze.

The retained coordinate or key identifies the cell in both the discovery and reconstruction code. The omitted direction, bounds and coordinate-construction statements only determine how candidates are generated before their first-discovery guard. Including them as in the previous selection would cost 616 tokens instead of 549.

Selected complete source lines: 13, 14, 16, 17, 18, 19, 20, 21, 22, 23, 26, 27, 28, 29, 30, 31, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46.
