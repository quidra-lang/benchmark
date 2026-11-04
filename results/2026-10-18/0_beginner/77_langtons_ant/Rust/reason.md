# Task B selection: 77_langtons_ant / Rust

## Common answer requirements

Read the direction after 300 complete steps, map it to U/R/D/L, and add a line between board and count.

## Supported analysis

The row/column deltas (-1,0), (0,1), (1,0), (0,-1) map direction 0–3 to U,R,D,L. Each step turns using the current color, flips that cell, and moves with the new direction. Read the direction binding after the simulation, then emit direction: D after the completed eleven board rows and before the black count. The result has thirteen lines.

The excerpt is copied verbatim from `main.rs`, in source order. Retained source lines: 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 27, 28, 29. Additional evidence is on line 8: `black[r as usize][c as usize] = !black[r as usize][c as usize];`.

## Minimization and alternatives

The bound, turn, flip and move show the exact observation point. The board-row output and the count write show the insertion point; the board character decisions and black-count arithmetic do not need to change. The prior selection used 249 tokens; this selection uses 287 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.
