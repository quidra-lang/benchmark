# Task B selection: 12_grade_letters / Quidra

## Common answer requirements

1. Identify the A/B decision boundary and its letter/index mapping.
2. Keep the same selected grade feeding both the student result and the grade-count update; preserve C/D/F and output order.

## Source evidence and minimization

The previous reviewed answer dependencies are retained; only equivalent range-header spelling or local type/index expressions changed. 1. Identify the A/B decision boundary and its letter/index mapping.
2. Keep the same selected grade feeding both the student result and the grade-count update; preserve C/D/F and output order.

Locations in main source: L2, L5, L6, L7.

All selected lines are complete, verbatim and in source order. The source evidence, the question, and documented language/library semantics support the answer. Inputs and branches unrelated to the answer are excluded. A modification-only question does not require unchanged implementation details solely to reconfirm the program remains correct. Imported library bindings are included when their contracts are used. Static types may replace inspection of user-defined implementations only for facts those types actually guarantee.

Alternative considered: the contiguous span between the first and last selected line and the full source. Those contain additional context, but do not reduce token cost. The selection is a reviewed sufficient candidate; exhaustive mathematical global minimality is not claimed.

Measurement: Task A 235; Task B 122. Tokenizer: metric/tokenizer.py, unchanged. Neither these lexical checks nor this selection establish execution/compilation of Task A.
