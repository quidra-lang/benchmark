# Task B selection: 33_yen_change / Kotlin

For amount 506, remaining starts independently at 506. The 500 denomination gives count 1, remainder 6, one piece and item 500x1; the following 100 denomination gives count 0 and emits nothing. Later divisions use remaining, while the original amount still labels the line.

Retain denomination order, case binding, remainder/count/piece updates and conditional output construction. No later-denomination trace is needed, but their common loop/output structure explains the dependency.

Selected complete source lines in `main.kt`: 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
