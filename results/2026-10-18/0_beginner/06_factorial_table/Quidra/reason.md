# Task B selection: 06_factorial_table / Quidra

## Common answer requirements

1. Locate the range endpoint and every representation/output dependency relevant to exact factorials through 15.
2. Explain how to produce sixteen increasing rows, including 0!, without overflow or lossy decimal output.

## Source evidence and minimization

The previous reviewed answer dependencies are retained; only equivalent range-header spelling or local type/index expressions changed. 1. Locate the range endpoint and every representation/output dependency relevant to exact factorials through 15.
2. Explain how to produce sixteen increasing rows, including 0!, without overflow or lossy decimal output.

Locations in main source: L1, L2.

All selected lines are complete, verbatim and in source order. The source evidence, the question, and documented language/library semantics support the answer. Inputs and branches unrelated to the answer are excluded. A modification-only question does not require unchanged implementation details solely to reconfirm the program remains correct. Imported library bindings are included when their contracts are used. Static types may replace inspection of user-defined implementations only for facts those types actually guarantee.

Alternative considered: the contiguous span between the first and last selected line and the full source. Those contain additional context, but do not reduce token cost. The selection is a reviewed sufficient candidate; exhaustive mathematical global minimality is not claimed.

Measurement: Task A 49; Task B 15. Tokenizer: metric/tokenizer.py, unchanged. Neither these lexical checks nor this selection establish execution/compilation of Task A.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 49; Task B 15.
