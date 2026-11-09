# Task B selection: 72_undo_redo_editor / Java

The parser first separates undo/redo command equality, then recognizes type followed by a space; its remainder begins at offset 5 and preserves the internal space of hello world. The other editing branch takes the decimal deletion payload from offset 7, parses 5, and retains the prefix of the buffer after clamping length at zero.

Keep command dispatch and editing payload/update expressions. Undo/redo history effects and final status printing are unnecessary to explain these two command payloads.

Selected complete source lines in `Main.java`: 10, 12, 19, 26, 29, 30, 31, 32, 33, 34, 35. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
