# Task B selection — 90_kruskal_mst / Julia

Weights are examined in ascending order, with each vertex initially its own root. After weights 3 and 4, E and C belong to the same component as A, while D is still separate; E–D (5) links the components. D and C then have the same root, so D–C (6) increments skipped. B–C (9) also increments skipped after A–B (7). G–F (8) links F to G and H, so E–H (10) joins the two remaining components and is the last accepted edge. The scan stops immediately after the seventh accepted edge; later edges never reach the same-root test and cannot increment skipped. The retained evidence traces examined weights, not overall weight or unused later edge records.

Selected complete source lines: 1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 15, 16, 17, 20, 22, 23, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 38.

With the benchmark tokenizer, this selection measures 413 tokens; the previous selection measured 485. The full source is 582 tokens.
