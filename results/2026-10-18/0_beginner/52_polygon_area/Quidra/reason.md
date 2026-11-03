# Task B selection: 52_polygon_area / Quidra

## Common answer requirements

[Code comprehension]

Locate the source code that includes the closing edge of each polygon in both calculations. Trace the contribution of the last-to-first edge of polygon 2 to the shoelace sum and to the perimeter. Explain how the implementation turns a possibly negative shoelace sum into a positive area while preserving the required order of floating-point perimeter additions.

## Answer supported by the selection

The edge loop visits each vertex in input order and selects its successor with `(i + 1) % len(polygon)`. At the last vertex that expression selects index zero, so the closing edge participates in both updates. For polygon 2, the closing edge is (8, 2) to (2, 1). It contributes 8*1 - 2*2 = 4 to `cross_sum`, and dx=6, dy=1, hence sqrt(37) to `perimeter`. The accumulated shoelace sum may be negative; `cross_sum.abs()` takes its magnitude before division by 2.0. `perimeter +=` executes once per edge in the collection loop, preserving the prescribed order of double-precision additions.

## Source evidence and minimization

The selected polygon record supplies the closing coordinates. The collection loops, successor expression, both accumulators, distance calculation and absolute-value/division steps are required to locate and explain the closing edge and operation order. `import math` supplies the sqrt and abs extension contracts. The other polygons and final presentation are unrelated to this trace.

Locations in main source: L1, L3, L5, L7, L8, L9, L10, L11, L12, L13, L14, L15, L16, L17, L18, L19.

All selected lines are complete, verbatim and in source order. The selected source, the question, and documented language/library semantics support the answer. The full source is a sufficient alternative but includes the unrelated material identified above; the retained selection is a reviewed lower-token sufficient candidate, without a claim of exhaustive global minimality.

Measurement: Task A 431; Task B 289. Tokenizer: metric/tokenizer.py, unchanged. These counts and source selections do not establish compilation or execution of Task A.

Execution verification: the revised program compiled and its stdout matched the Python reference, because the historical Quidra source fails current compilation exactly.
