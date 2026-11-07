# Task B selection: 72_undo_redo_editor / Python

The initial edits leave `hello ` with a trailing space. Typing there saves that snapshot and produces `hello there`. The two successful undo operations restore `hello ` and then `hello world`, moving the displaced snapshots onto redo. Redo restores `hello ` and leaves `hello there` redoable. Typing friend stores `hello `, appends to its trailing space, and clears redo. The following redo sees empty history and leaves `hello friend` unchanged.

The selected command prefix and stack initialization establish the starting state. The guards, last-in-first-out stack transfers, redo reset, and edit expressions supply the remaining dependencies. Status messages and final formatting only report state and add no evidence to this trace.

Selected complete source lines in order are 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 16, 17, 18, 19, 20, 21, 23, 24, 25, 26, 27, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38. The excerpt uses documented library semantics and the Task B assumptions.

Task A uses 381 tokens. Task B uses 289 tokens.

## Current token measurement

Task A: **378 tokens**. Task B: **286 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
