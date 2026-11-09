# Task B selection: 70_game_of_life / Kotlin

A fresh next board is allocated, then every cell resets neighbors and scans eight offsets excluding (0,0). For corner (0,0), nr=-1 fails the first bounds condition, so short-circuit && skips board access. The next cell is live for three neighbors, or for a currently live cell with two; reads use board and writes use next until the entire traversal finishes and board is rebound.

Keep the complete one-generation operation, including allocation and final rebinding. Initial pattern, generation printing and lifetime total are outside this routine.

Selected complete source lines in `main.kt`: 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
