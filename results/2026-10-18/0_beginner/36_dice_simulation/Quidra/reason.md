# Task B selection: 36_dice_simulation / Quidra

## Common answer requirements

Trace seed 12345 through both generator state updates, derive both dice and their counted sum, and establish update-before-use and reuse of the newly updated state for the second generation.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Source evidence and minimization

The previous reviewed answer dependencies are retained; only equivalent range-header spelling or local type/index expressions changed. Trace seed 12345 through both generator state updates, derive both dice and their counted sum, and establish update-before-use and reuse of the newly updated state for the second generation.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

Locations in main source: L1, L4, L5, L6, L7, L8.

All selected lines are complete, verbatim and in source order. The source evidence, the question, and documented language/library semantics support the answer. Inputs and branches unrelated to the answer are excluded. A modification-only question does not require unchanged implementation details solely to reconfirm the program remains correct. Imported library bindings are included when their contracts are used. Static types may replace inspection of user-defined implementations only for facts those types actually guarantee.

Alternative considered: the contiguous span between the first and last selected line and the full source. Those contain additional context, but do not reduce token cost. The selection is a reviewed sufficient candidate; exhaustive mathematical global minimality is not claimed.

Measurement: Task A 215; Task B 110. Tokenizer: metric/tokenizer.py, unchanged. Neither these lexical checks nor this selection establish execution/compilation of Task A.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 215; Task B 110.
