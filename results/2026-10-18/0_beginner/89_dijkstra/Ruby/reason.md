# Task B selection — 89_dijkstra / Ruby

Move the zero-distance seed from A to G (index 6). The selected predecessor initialization and walk show that -1 denotes no predecessor, rather than encoding A; G becomes the endpoint without rewriting that stopping rule. Keep the ascending destination loop, existing path direction and output separators. The displayed path then starts at G and contains only G for G itself. The graph data and relaxation calculations have no changed dependency.

Selected complete source lines: 1, 12, 14, 26, 28, 29, 30, 31, 32, 33.

With the benchmark tokenizer, this selection measures 126 tokens; the previous selection measured 81. The full source is 505 tokens.
