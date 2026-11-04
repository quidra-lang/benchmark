# Task B selection: 72_undo_redo_editor / Java

## Common answer requirements

Trace the requested stack history, exact restored contents and invalidation of an abandoned redo.

## Supported analysis

Deleting 5 from hello world leaves hello followed by one space. Typing there saves that snapshot and produces hello there. Undo restores the trailing-space snapshot; undo again restores hello world, leaving deletion next to redo and typing there after it. Redo restores the trailing-space snapshot and leaves there redoable. Typing friend saves that state, clears the redo branch and appends to the existing space to give hello friend. The final redo sees an empty history and changes nothing.

The excerpt is copied verbatim from `Main.java`, in source order. Retained source lines: 6, 7, 8, 9, 10, 12, 13, 15, 16, 17, 18, 19, 20, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33.

## Minimization and alternatives

The command prefix, stack initializers, guarded transfers, reset and string operations determine the trace. Output-only status assignments and writes add no information about whether buffer or stack state changes. The prior selection used 532 tokens; this selection uses 469 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.
