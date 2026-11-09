# Task B selection: 10_fibonacci / Kotlin

Initial terms are 1,1. Each of thirty iterations saves the current first value, then advances the pair to the old second and the sum, giving F(3)=2. The list and separately named sum use signed 32-bit integer arithmetic; all requested terms and their total fit, so no division or rounding occurs. The integer type alone would not guarantee unbounded exact arithmetic for a larger request.

Keep initialization, count bound, ordered updates, term storage and final reduction. Output joining and literal labels are unnecessary because the question stops when sequence and total are available.

Selected complete source lines in `main.kt`: 2, 3, 4, 5, 6, 7, 8, 9, 10, 11. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
