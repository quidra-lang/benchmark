# Task B selection — 89_dijkstra / J

Move the zero in the initial distance vector from the head to the last position, with infinity in the first six slots. The zero-based index of G is 6. The _1 predecessor is a sentinel, so it still stops the walk at the new root without hard-coding G in the path loop. Keep the ascending destination loop, existing path direction and output separators. The displayed path then starts at G and contains only G for G itself. The graph data and relaxation calculations have no changed dependency.

Selected complete source lines: 2, 10, 11, 27, 29, 30, 31, 32, 33, 34, 35.

With the benchmark tokenizer, this selection measures 151 tokens; the previous selection measured 64. The full source is 485 tokens.
