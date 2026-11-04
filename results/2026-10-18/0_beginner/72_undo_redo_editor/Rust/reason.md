# Task B selection: 72_undo_redo_editor / Rust

## Common answer requirements

Trace the requested stack history, exact restored contents and invalidation of an abandoned redo.

## Supported analysis

Deleting 5 from hello world leaves hello followed by one space. Typing there saves that snapshot and produces hello there. Undo restores the trailing-space snapshot; undo again restores hello world, leaving deletion next to redo and typing there after it. Redo restores the trailing-space snapshot and leaves there redoable. Typing friend saves that state, clears the redo branch and appends to the existing space to give hello friend. The final redo sees an empty history and changes nothing.

The excerpt is copied verbatim from `main.rs`, in source order. Retained source lines: 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 17, 18, 19, 20, 21, 22, 23, 24, 25, 29, 30, 31, 32, 33, 37, 38, 39, 40, 41, 42, 43, 44, 45.

## Minimization and alternatives

The command prefix, stack initializers, guarded transfers, reset and string operations determine the trace. Output-only status assignments and writes add no information about whether buffer or stack state changes. The prior selection used 497 tokens; this selection uses 411 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.
