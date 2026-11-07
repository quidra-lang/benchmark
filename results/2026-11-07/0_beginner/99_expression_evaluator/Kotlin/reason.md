# Task B selection: 99_expression_evaluator / Kotlin

Starting with height=7 in the existing table, assignment parsing skips the name/equals tokens and evaluates the expression before committing. Term evaluates 100 then parenthesized height-7 = 0; the explicit zero-divisor guard throws before Expression can advance to the + bonus term, so no bonus lookup occurs. The catch emits error: division by zero and the deferred variable-table write never runs, preserving height=7.

The input line containing width = 12 and height = width - 5 establishes the previous height 7 without tracing unrelated assignments. Tokenization, parser state/precedence/lookup, zero-divisor throw, deferred assignment and error output are retained; success-only unrelated expression printing is omitted.

Selected complete source lines in `main.kt`: 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 60, 61, 62. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
