# Task B selection — 86_convex_hull / Zig

Ascending x then y starts the lower scan at (-6,-2), (-6,1), (-6,3); the third point gives cross product zero and removes (-6,1). In the reverse scan the last three points are (-6,3), (-6,1), (-6,-2); the same nonpositive test removes the middle again. Keeping only positive turns eliminates collinear interior points. The join takes the ascending lower chain followed by the reverse upper chain with the last point of each omitted, so the shared extrema appear once and the hull starts at (-6,-2) counterclockwise. The retained sort, cross product and join carry these facts without area or presentation code.

Selected complete source lines: 3, 4, 5, 7, 8, 9, 15, 16, 17, 19, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 38, 39, 40.

With the benchmark tokenizer, this selection measures 712 tokens; the previous selection measured 716. The full source is 1108 tokens.

## Current token measurement

Task A: **1105 tokens**. Task B: **711 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
