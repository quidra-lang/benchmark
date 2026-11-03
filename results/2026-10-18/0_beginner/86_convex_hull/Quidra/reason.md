# Task B selection: 86_convex_hull / Quidra

## Common answer requirements

[Code comprehension]

Using the source, trace how the three points with x-coordinate -6 are processed during chain construction. Explain which cross-product comparison prevents a point in the middle of a boundary edge from becoming a hull corner. Then identify how the implementation joins the completed chains without duplicating their endpoints, preserving the required starting vertex and counterclockwise order.

## Answer supported by the selection

`collections.lex_order(points)` orders the two-element coordinate arrays by x and then y, and the indexed gather materializes that order. The lower chain therefore begins (-6,-2), (-6,1), (-6,3). Their integer cross product is zero, so the <=0 condition removes the middle point (-6,1) before adding (-6,3). A later point causes (-6,3) to leave the lower chain, whose final contents are [(-6,-2),(1,-5),(7,-1),(8,4)]. The upper chain traverses the reversed sort: when the x=-6 points arrive, (-6,3) removes (-3,4) with cross=-9, then (-6,1) is temporarily appended; adding (-6,-2) gives cross zero and removes (-6,1). Its final contents are [(8,4),(2,8),(-3,7),(-6,3),(-6,-2)]. Thus the <=0 rule excludes points in the middle of boundary edges as well as right turns. The two final `.take()` calls remove lower endpoint (8,4) and upper endpoint (-6,-2); concatenating lower then upper leaves each shared endpoint once, begins at (-6,-2), and preserves counterclockwise order.

## Source evidence and minimization

The cross function, full chain implementation and all input points are required to trace the collinear points and subsequent chain updates. The lexicographic ordering, reversed upper traversal, endpoint removals and concatenation establish the final vertex ordering and absence of duplicated endpoints. `import collections` supplies lex_order and mutable array push/take semantics. Area accumulation and output formatting are independent of these chain-construction questions and are omitted.

Locations in main source: L1, L3, L4, L6, L7, L8, L9, L10, L11, L12, L14, L15, L16, L17, L18, L19, L20, L21, L22, L23.

All selected lines are complete, verbatim and in source order. The selected source, the question, and documented language/library semantics support the answer. The full source is a sufficient alternative but includes the unrelated material identified above; the retained selection is a reviewed lower-token sufficient candidate, without a claim of exhaustive global minimality.

Measurement: Task A 604; Task B 424. Tokenizer: metric/tokenizer.py, unchanged. These counts and source selections do not establish compilation or execution of Task A.
