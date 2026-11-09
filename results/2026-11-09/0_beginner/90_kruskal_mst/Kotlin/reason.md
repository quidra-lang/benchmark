# Task B selection: 90_kruskal_mst / Kotlin

Weight order accepts G-H 2, C-E 3, A-C 4, D-E 5, rejects C-D 6 as a cycle, accepts A-B 7, F-G 8, rejects B-C 9, then accepts E-H 10 as edge seven. Total is 39 and skipped is 2. Union-Find detects equal roots; accepted increments before the immediate seven-edge break, so later edges are not examined. Printed endpoint min/max normalizes names.

Retain all original edges, ordering, root/union/reject/stop logic and exact reports. Imports and entry-point/culture scaffolding add no Kruskal evidence.

Selected complete source lines in `main.kt`: 1, 2, 3, 4, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
