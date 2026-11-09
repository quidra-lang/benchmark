# Task B selection: 55_grid_paths / Java

For each false/true obstacles case, new DP storage is zero-filled and its [0,0] entry is explicitly assigned 1. This represents the unique empty route already at the start; zero would incorrectly remove the base source of all path counts. The same assignment is inside the case loop, so both cases receive it.

Only the case loop and allocation/base assignment are needed. Propagating later grid cells and final totals would exceed the base-state question.

Selected complete source lines in `Main.java`: 4, 5, 6. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
