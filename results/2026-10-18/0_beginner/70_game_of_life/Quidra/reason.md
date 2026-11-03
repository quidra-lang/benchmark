# Task B selection: 70_game_of_life / Quidra

## Common answer requirements

Trace generation-0 neighbors at zero-based (0,1) and (1,0), their generation-1 states, exclusion of out-of-board neighbors, and isolation of every count from earlier writes during that generation.

## Source evidence and minimization

The previous reviewed answer dependencies are retained; only equivalent range-header spelling or local type/index expressions changed. Trace generation-0 neighbors at zero-based (0,1) and (1,0), their generation-1 states, exclusion of out-of-board neighbors, and isolation of every count from earlier writes during that generation.

Locations in main source: L1, L8, L9, L10, L11, L12, L13, L14, L15, L16, L17, L18, L19, L20, L21, L22, L23.

All selected lines are complete, verbatim and in source order. The source evidence, the question, and documented language/library semantics support the answer. Inputs and branches unrelated to the answer are excluded. A modification-only question does not require unchanged implementation details solely to reconfirm the program remains correct. Imported library bindings are included when their contracts are used. Static types may replace inspection of user-defined implementations only for facts those types actually guarantee.

Alternative considered: the contiguous span between the first and last selected line and the full source. Those contain additional context, but do not reduce token cost. The selection is a reviewed sufficient candidate; exhaustive mathematical global minimality is not claimed.

Measurement: Task A 474; Task B 349. Tokenizer: metric/tokenizer.py, unchanged. Neither these lexical checks nor this selection establish execution/compilation of Task A.
