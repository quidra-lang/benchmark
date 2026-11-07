# Task B selection — 90_kruskal_mst / Quidra

Weights are examined in ascending order, with each vertex initially its own root. After weights 3 and 4, E and C belong to the same component as A, while D is still separate; E–D (5) links the components. D and C then have the same root, so D–C (6) increments skipped. B–C (9) also increments skipped after A–B (7). G–F (8) links F to G and H, so E–H (10) joins the two remaining components and is the last accepted edge. The scan stops immediately after the seventh accepted edge; later edges never reach the same-root test and cannot increment skipped. The retained evidence traces examined weights, not overall weight or unused later edge records.

Selected complete source lines: 1, 4, 5, 6, 7, 9, 10, 11, 12, 13, 15, 16, 17, 20, 22, 23, 25, 26, 27, 28, 29, 30, 31, 33, 34, 35, 36, 37, 38, 39, 42, 43, 44.

With the benchmark tokenizer, this selection measures 345 tokens; the previous selection measured 351. The full source is 481 tokens.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 481; Task B 345.

Measurement: Task A 481; Task B 345. Tokenizer: metric/tokenizer.py, unchanged.

## Current token measurement

The tuple-array fixture types are inferred from the retained nonempty literal entries using Core numeric and string literal defaults; removing the redundant annotations does not remove a fact needed for this answer.

Task A: **470 tokens**. Task B: **334 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
