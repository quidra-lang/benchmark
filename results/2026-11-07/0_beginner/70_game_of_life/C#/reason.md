# Task B selection: 70_game_of_life / C#

A fresh next board is allocated, then every cell resets neighbors and scans eight offsets excluding (0,0). For corner (0,0), nr=-1 fails the first bounds condition, so short-circuit && skips board access. The next cell is live for three neighbors, or for a currently live cell with two; reads use board and writes use next until the entire traversal finishes and board is rebound.

Keep the complete one-generation operation, including allocation and final rebinding. Initial pattern, generation printing and lifetime total are outside this routine.

Selected complete source lines in `Program.cs`: 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
