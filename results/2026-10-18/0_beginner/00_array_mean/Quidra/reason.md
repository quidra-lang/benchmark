# Task B selection: 00_array_mean / Quidra

## Common answer requirements

1. Identify the existing sum/mean and original-length denominator that must change.
2. Sum and count only elements at least 50; choose zero before division when that count is zero.
3. Leave the seven input values and existing single-line two-decimal presentation unchanged.

## Source evidence and minimization

The previous reviewed answer dependencies are retained; only equivalent range-header spelling or local type/index expressions changed. 1. Identify the existing sum/mean and original-length denominator that must change.
2. Sum and count only elements at least 50; choose zero before division when that count is zero.
3. Leave the seven input values and existing single-line two-decimal presentation unchanged.

Locations in main source: L1, L4.

All selected lines are complete, verbatim and in source order. The source evidence, the question, and documented language/library semantics support the answer. Inputs and branches unrelated to the answer are excluded. A modification-only question does not require unchanged implementation details solely to reconfirm the program remains correct. Imported library bindings are included when their contracts are used. Static types may replace inspection of user-defined implementations only for facts those types actually guarantee.

Alternative considered: the contiguous span between the first and last selected line and the full source. Those contain additional context, but do not reduce token cost. The selection is a reviewed sufficient candidate; exhaustive mathematical global minimality is not claimed.

Measurement: Task A 61; Task B 14. Tokenizer: metric/tokenizer.py, unchanged. Neither these lexical checks nor this selection establish execution/compilation of Task A.
