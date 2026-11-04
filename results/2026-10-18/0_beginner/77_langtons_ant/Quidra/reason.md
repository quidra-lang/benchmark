# Task B selection: 77_langtons_ant / Quidra

## Common answer requirements

Read the direction after 300 complete steps, map it to U/R/D/L, and add a line between board and count.

## Supported analysis

The row/column deltas (-1,0), (0,1), (1,0), (0,-1) map direction 0–3 to U,R,D,L. Each step turns using the current color, flips that cell, and moves with the new direction. Read the direction binding after the simulation, then emit direction: D after the completed eleven board rows and before the black count. The result has thirteen lines.

The excerpt is copied verbatim from `main.qui`, in source order. Retained source lines: 4, 5, 6, 7, 8, 9, 10, 11, 13, 19, 20. Additional evidence is on line 9: `black[row][column] = not black[row][column]`.

## Minimization and alternatives

The bound, turn, flip and move show the exact observation point. The board-row output and the count write show the insertion point; the board character decisions and black-count arithmetic do not need to change. The prior selection used 186 tokens; this selection uses 199 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 336; Task B 199.

Measurement: Task A 336; Task B 199. Tokenizer: metric/tokenizer.py, unchanged.
