# Task B selection — 89_dijkstra / Dart

Move the zero-distance seed from vertex A (index 0) to G (index 6) and change the explicit index-0 stop inside the predecessor walk to that same source index. The walk records the vertex before the stop, so G is included even for the zero-length route. Keep the ascending destination loop, existing path direction and output separators. The displayed path then starts at G and contains only G for G itself. The graph data and relaxation calculations have no changed dependency.

Selected complete source lines: 22, 37, 39, 41, 42, 43, 44, 46.

With the benchmark tokenizer, this selection measures 147 tokens; the previous selection measured 102. The full source is 719 tokens.
