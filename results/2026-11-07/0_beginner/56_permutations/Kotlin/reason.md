# Task B selection: 56_permutations / Kotlin

Search begins with an empty prefix and four unused flags. At each depth, ascending index choices mark a flag, append its ABCD character, recurse and restore the flag. Length four emits and increments the shared count: first 1: ABCD, last 24: DCBA. Returning from ADCB restores the A branch before the B branch begins with BACD; all 4! distinct choices are exhausted.

Keep recursion, shared count/flags and initial call, because numbering and restoration depend on them. Entry-point wrappers, imports and unrelated formatting setup are omitted.

Selected complete source lines in `main.kt`: 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
