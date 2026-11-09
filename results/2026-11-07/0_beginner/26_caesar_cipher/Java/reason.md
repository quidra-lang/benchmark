# Task B selection: 26_caesar_cipher / Java

The callable maps A..Z and a..z relative to their separate bases, adds shift with +26 before mod 26, and preserves nonletters using the negative-base branch. With shift 3, Z wraps to C and the following comma is copied. C#/Kotlin mapping creates a new string; Java appends to local StringBuilder storage then returns an immutable string. The named encrypted result is passed back with -3 for decryption.

Keep the transformation body, concrete call and decrypt call; the intermediate print adds no dependency. Standard mapping/builder/string semantics establish mutation versus value construction.

Selected complete source lines in `Main.java`: 2, 3, 4, 5, 6, 7, 8, 9, 12, 14. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
