# Task B selection: 43_run_length_encoding / Kotlin

The second text is twelve W, B, twelve W, BBB; maximal same-character runs encode to 12W1B12W3B. The decoder parses the entire digit sequence with digit-plus, repeats the following letter, and reconstructs the original 28 characters from encoded text. Its complete line is WWWWWWWWWWWWBWWWWWWWWWWWWBBB -> 12W1B12W3B -> WWWWWWWWWWWWBWWWWWWWWWWWWBBB.

Keep that input line, regex definitions where separate, and encoding/decoding/output chain. Other data and entry-point scaffolding do not help this trace.

Selected complete source lines in `main.kt`: 3, 6, 7, 8, 9, 10, 11, 12. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
