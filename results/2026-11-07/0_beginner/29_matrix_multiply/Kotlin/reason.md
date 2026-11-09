# Task B selection: 29_matrix_multiply / Kotlin

First-row second-column pairs are (3,4),(-2,2),(5,-1),(1,7), with products 12,-4,-5,7 and sum 10. Column index 1 is stored in row[1] and emitted as the second width-five field. The reduction evaluates every k, including row-2 A value zero multiplied by its B element; there is no zero-skipping guard and ordinary multiplication does not short-circuit.

Keep the two matrices, complete dot-product loops, row placement and emission. These are necessary to distinguish an ordinary zero product from a conditional optimization.

Selected complete source lines in `main.kt`: 2, 3, 4, 5, 6, 7. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
