# Task B selection: 79_n_queens / Java

Reverse candidate column order at every depth; the search still exhausts the same safe placements and counts 1 at each complete board. Size-eight first solution becomes zero-based columns [7,3,0,2,5,1,6,4], the mirror of the ascending first solution. Prior-row checks reject shared columns/diagonals; later writes replace only the current-depth slot, and prior-prefix checks ignore stale deeper slots, so recursion implicitly restores choices. First-result retention copies positions once before row rendering; counts for N=4..8 remain unchanged.

Search state, rejection/recursion/counting, first-solution retention, size selection and row rendering all support this whole-run modification. Other formatting setup is irrelevant.

Selected complete source lines in `Main.java`: 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
