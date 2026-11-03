# Task B selection: 22_char_frequency / Python

## Common answer requirements

Identify case-folding/filtering/count indexing and output ordering; separate A-Z/a-z, ignore other characters, uppercase first then lowercase, emit only present letters with preserved case and format.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Source evidence and minimization

Retain the existing question-specific semantic selection, and add the actual import binding for each selected standard-library call. For the CSV trace, include the header to explain the data slice offset. These are required source facts, not additional implementation inspection.

Locations in main source: L1, L4, L5.

All selected lines are complete, verbatim and in source order. The source evidence, the question, and documented language/library semantics support the answer. Inputs and branches unrelated to the answer are excluded. A modification-only question does not require unchanged implementation details solely to reconfirm the program remains correct. Imported library bindings are included when their contracts are used. Static types may replace inspection of user-defined implementations only for facts those types actually guarantee.

Alternative considered: the contiguous span between the first and last selected line and the full source. Those contain additional context, but do not reduce token cost. The selection is a reviewed sufficient candidate; exhaustive mathematical global minimality is not claimed.

Measurement: Task A 99; Task B 57. Tokenizer: metric/tokenizer.py, unchanged. Neither these lexical checks nor this selection establish execution/compilation of Task A.
