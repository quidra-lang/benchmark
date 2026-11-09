# Task B selection: 72_undo_redo_editor / Kotlin

The parser first separates undo/redo command equality, then recognizes type followed by a space; its remainder begins at offset 5 and preserves the internal space of hello world. The other editing branch takes the decimal deletion payload from offset 7, parses 5, and retains the prefix of the buffer after clamping length at zero.

Keep command dispatch and editing payload/update expressions. Undo/redo history effects and final status printing are unnecessary to explain these two command payloads.

Selected complete source lines in `main.kt`: 7, 9, 10, 16, 22, 25, 26, 27, 28, 29, 30. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
