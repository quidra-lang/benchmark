# Task B selection: 84_sales_csv_summary / Python

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Source evidence and minimization

Retain the existing question-specific semantic selection, and add the actual import binding for each selected standard-library call. For the CSV trace, include the header to explain the data slice offset. These are required source facts, not additional implementation inspection.

Locations in main source: L1, L3, L4, L5, L9, L10, L13, L15, L17, L18, L20, L21, L22, L23, L25, L26, L29, L31.

All selected lines are complete, verbatim and in source order. The source evidence, the question, and documented language/library semantics support the answer. Inputs and branches unrelated to the answer are excluded. A modification-only question does not require unchanged implementation details solely to reconfirm the program remains correct. Imported library bindings are included when their contracts are used. Static types may replace inspection of user-defined implementations only for facts those types actually guarantee.

Alternative considered: the contiguous span between the first and last selected line and the full source. Those contain additional context, but do not reduce token cost. The selection is a reviewed sufficient candidate; exhaustive mathematical global minimality is not claimed.

Measurement: Task A 613; Task B 313. Tokenizer: metric/tokenizer.py, unchanged. Neither these lexical checks nor this selection establish execution/compilation of Task A.
