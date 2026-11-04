# Task B selection — 89_dijkstra / Zig

Move the zero-distance seed from vertex A (index 0) to G (index 6) and change the explicit index-0 stop inside the predecessor walk to that same source index. The walk records the vertex before the stop, so G is included even for the zero-length route. Keep the ascending destination loop, existing path direction and output separators. The displayed path then starts at G and contains only G for G itself. The graph data and relaxation calculations have no changed dependency.

Selected complete source lines: 17, 35, 36, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51.

With the benchmark tokenizer, this selection measures 272 tokens; the previous selection measured 158. The full source is 1019 tokens.
