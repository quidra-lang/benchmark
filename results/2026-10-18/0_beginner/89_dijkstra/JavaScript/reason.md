# Task B selection — 89_dijkstra / JavaScript

Move the zero-distance seed from A to G (index 6). The selected predecessor initialization and walk show that -1 denotes no predecessor, rather than encoding A; G becomes the endpoint without rewriting that stopping rule. Keep the ascending destination loop, existing path direction and output separators. The displayed path then starts at G and contains only G for G itself. The graph data and relaxation calculations have no changed dependency.

Selected complete source lines: 1, 12, 13, 28, 30, 31.

With the benchmark tokenizer, this selection measures 171 tokens; the previous selection measured 118. The full source is 630 tokens.
