# Task B selection: 79_n_queens / Quidra

## Common answer requirements

Locate the column enumeration shared by every row and board size; reverse it to n-1 through 0 while retaining exhaustive search and conflict checks. Identify first-solution capture and size-eight output dependency.

## Source evidence and minimization

The previous reviewed answer dependencies are retained; only equivalent range-header spelling or local type/index expressions changed. Locate the column enumeration shared by every row and board size; reverse it to n-1 through 0 while retaining exhaustive search and conflict checks. Identify first-solution capture and size-eight output dependency.

Locations in main source: L7.

All selected lines are complete, verbatim and in source order. The source evidence, the question, and documented language/library semantics support the answer. Inputs and branches unrelated to the answer are excluded. A modification-only question does not require unchanged implementation details solely to reconfirm the program remains correct. Imported library bindings are included when their contracts are used. Static types may replace inspection of user-defined implementations only for facts those types actually guarantee.

Alternative considered: the contiguous span between the first and last selected line and the full source. Those contain additional context, but do not reduce token cost. The selection is a reviewed sufficient candidate; exhaustive mathematical global minimality is not claimed.

Measurement: Task A 374; Task B 11. Tokenizer: metric/tokenizer.py, unchanged. Neither these lexical checks nor this selection establish execution/compilation of Task A.
