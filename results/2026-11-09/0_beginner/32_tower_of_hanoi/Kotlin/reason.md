# Task B selection: 32_tower_of_hanoi / Kotlin

For Hanoi(4,A,C,B), first solve (3,A,B,C), emit disk 4 from A to C, then solve (3,B,C,A); n=0 returns zero. Counts combine left+1+right, yielding 15 at the top. Primitive char arguments are passed by value, so role permutation changes callee parameters without modifying caller bindings or any shared peg storage.

The recursive signature/body and top-level call establish argument roles, emissions and count combination. No peg-state structure exists to include.

Selected complete source lines in `main.kt`: 1, 2, 3, 4, 5, 6, 9. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
