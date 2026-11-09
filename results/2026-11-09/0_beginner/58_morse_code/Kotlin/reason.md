# Task B selection: 58_morse_code / Kotlin

The decoder already reads encoded Morse text, splitting words on space-slash-space and letters on one space. Exact dictionary/map key lookup maps . to E and .- to A independently, then joins letters without separators and words with one space. It does not use original message letters as fallback, so only an independent decoder input boundary would be needed if exposing it separately.

Keep the reverse-table relationship and complete decoding path. Original message text, encoding and output lines are unnecessary to prove independent token lookup; the table is retained to establish the two concrete mappings.

Selected complete source lines in `main.kt`: 2, 3, 4, 8, 9. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
