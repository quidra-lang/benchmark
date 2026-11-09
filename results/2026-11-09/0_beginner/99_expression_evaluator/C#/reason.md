# Task B selection: 99_expression_evaluator / C#

Starting with height=7 in the existing table, assignment parsing skips the name/equals tokens and evaluates the expression before committing. Term evaluates 100 then parenthesized height-7 = 0; the explicit zero-divisor guard throws before Expression can advance to the + bonus term, so no bonus lookup occurs. The catch emits error: division by zero and the deferred variable-table write never runs, preserving height=7.

The input line containing width = 12 and height = width - 5 establishes the previous height 7 without tracing unrelated assignments. Tokenization, parser state/precedence/lookup, zero-divisor throw, deferred assignment and error output are retained; success-only unrelated expression printing is omitted.

Selected complete source lines in `Program.cs`: 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 31, 32, 33, 34, 35, 40, 41, 42, 44, 45, 46, 47, 48, 49, 51, 52, 53, 54, 55, 56, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
