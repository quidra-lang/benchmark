# Task B selection: 31_pascal_triangle / Kotlin

Row 0 is [1]. The next row allocates length two and explicitly supplies endpoint ones; its interior range is empty because there is no interior index. Therefore row 1 is [1,1] without reading missing neighbors. Kotlin expresses the same guard in its List initializer: both generated indices select the endpoint branch.

Keep initial row, next allocation/endpoint branch and interior bound/update. Printing and the twelve-row outer count do not establish this one boundary transition.

Selected complete source lines in `main.kt`: 2, 5. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
