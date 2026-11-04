# Task B selection — 89_dijkstra / Quidra

Change the shared start index from 0 to 6. Both the zero-distance assignment and the initial ready flag use it. The -1 predecessor sentinel stays unchanged: the new start has no predecessor. Keep the ascending destination loop, existing path direction and output separators. The displayed path then starts at G and contains only G for G itself. The graph data and relaxation calculations have no changed dependency.

Selected complete source lines: 3, 10, 12, 13, 14, 28, 30, 31, 32, 33, 34.

With the benchmark tokenizer, this selection measures 141 tokens; the previous selection measured 164. The full source is 520 tokens.

Measurement: Task A 520; Task B 141. Tokenizer: metric/tokenizer.py, unchanged.
