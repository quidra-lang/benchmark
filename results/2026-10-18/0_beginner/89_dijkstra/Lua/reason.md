# Task B selection — 89_dijkstra / Lua

Move the zero-distance seed from A to G (index 7). The selected predecessor initialization and walk show that nil denotes no predecessor, rather than encoding A; G becomes the endpoint without rewriting that stopping rule. Keep the ascending destination loop, existing path direction and output separators. The displayed path then starts at G and contains only G for G itself. The graph data and relaxation calculations have no changed dependency.

Selected complete source lines: 1, 12, 14, 29, 30, 31, 32, 33, 34, 35.

With the benchmark tokenizer, this selection measures 173 tokens; the previous selection measured 109. The full source is 682 tokens.

## Current token measurement

Task A: **680 tokens**. Task B: **173 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
