# Task B selection: 13_diamond_pattern / Kotlin

This source already keeps emitted-row ordinal row independently of size i. The single range spans ordinals 1..9; i grows through 5 then becomes 2*n-row, giving size 4 at row 6 without repeating the widest row. Add row k: and one space at its existing emission using row; preserve the space/star construction. The equivalent expanding/shrinking ranges are row<=n and row>n within this loop.

Keep n, the complete row range, the piecewise size and emission. There are no two physical output sites or separate loops in this implementation to invent.

Selected complete source lines in `main.kt`: 2, 3, 4, 5, 6. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
