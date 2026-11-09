# Task B selection: 86_convex_hull / Kotlin

Sorting is increasing x then y; reversing that sorted sequence begins (8,4),(7,-1), regardless of original input order. For each new point, while two points remain and their cross product with it is <=0, remove the chain tail; then append the current point. Repeating the test eliminates successive non-left turns, producing the complete upper chain.

Keep point input/order, upper-call reverse, chain mutation loop and cross definition. Lower construction is incidental on a retained line, but concatenation, area and rendering are unrelated and excluded.

Selected complete source lines in `main.kt`: 3, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 20, 21, 22, 23, 24, 25, 26. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
