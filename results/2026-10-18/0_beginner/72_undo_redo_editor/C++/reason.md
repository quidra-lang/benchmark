# Task B selection: 72_undo_redo_editor / C++

## Common answer requirements

Trace the requested stack history, exact restored contents and invalidation of an abandoned redo.

## Supported analysis

Deleting 5 from hello world leaves hello followed by one space. Typing there saves that snapshot and produces hello there. Undo restores the trailing-space snapshot; undo again restores hello world, leaving deletion next to redo and typing there after it. Redo restores the trailing-space snapshot and leaves there redoable. Typing friend saves that state, clears the redo branch and appends to the existing space to give hello friend. The final redo sees an empty history and changes nothing.

The excerpt is copied verbatim from `main.cpp`, in source order. Retained source lines: 7, 8, 9, 10, 11, 12, 13, 15, 16, 17, 18, 19, 20, 21, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35.

## Minimization and alternatives

The command prefix, stack initializers, guarded transfers, reset and string operations determine the trace. Output-only status assignments and writes add no information about whether buffer or stack state changes. The prior selection used 543 tokens; this selection uses 481 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.

## Current token measurement

Task A: **606 tokens**. Task B: **472 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
