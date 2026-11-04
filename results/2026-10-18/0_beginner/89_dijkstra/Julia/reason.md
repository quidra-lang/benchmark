# Task B selection — 89_dijkstra / Julia

Move the zero-distance seed from A to G (index 7). The selected predecessor initialization and walk show that 0 denotes no predecessor, rather than encoding A; G becomes the endpoint without rewriting that stopping rule. Keep the ascending destination loop, existing path direction and output separators. The displayed path then starts at G and contains only G for G itself. The graph data and relaxation calculations have no changed dependency.

Selected complete source lines: 2, 22, 24, 36, 38, 39, 40, 41, 42, 43.

With the benchmark tokenizer, this selection measures 137 tokens; the previous selection measured 88. The full source is 637 tokens.
