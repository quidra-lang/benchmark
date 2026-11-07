# Task B selection: 14_moving_average / Kotlin

The named window controls first endpoint w-1, the lower sum bound i-w+1 and real-valued division; i+1 is the day label. For w=5, endpoints 4..9 emit day 5 through day 10, six results. For w=11 the range is empty: add a single missing-window message before/around the loop when w exceeds sales length. Preserve double division and fixed two-place formatting.

All input/window/bounds/sum/division/output dependencies matter to this operation-wide extension. Entry-point/import scaffolding and unrelated behavior are excluded.

Selected complete source lines in `main.kt`: 4, 5, 6, 7, 8, 9, 10. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
