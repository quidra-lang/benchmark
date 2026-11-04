# Task B selection: 01_sum_max_min / Quidra

## Common answer requirements

1. Trace the contribution of -23 to the sum and the minimum for the actual array.
2. Explain why both occurrences of 5 contribute to addition, but duplicates do not change the minimum.

## Source evidence and minimization

The previous reviewed answer dependencies are retained; only equivalent range-header spelling or local type/index expressions changed. 1. Trace the contribution of -23 to the sum and the minimum for the actual array.
2. Explain why both occurrences of 5 contribute to addition, but duplicates do not change the minimum.

Locations in main source: L1, L3, L4.

All selected lines are complete, verbatim and in source order. The source evidence, the question, and documented language/library semantics support the answer. Inputs and branches unrelated to the answer are excluded. A modification-only question does not require unchanged implementation details solely to reconfirm the program remains correct. Imported library bindings are included when their contracts are used. Static types may replace inspection of user-defined implementations only for facts those types actually guarantee.

Alternative considered: the contiguous span between the first and last selected line and the full source. Those contain additional context, but do not reduce token cost. The selection is a reviewed sufficient candidate; exhaustive mathematical global minimality is not claimed.

Measurement: Task A 95; Task B 94. Tokenizer: metric/tokenizer.py, unchanged. Neither these lexical checks nor this selection establish execution/compilation of Task A.
