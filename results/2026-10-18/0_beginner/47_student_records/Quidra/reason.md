# Task B selection: 47_student_records / Quidra

## Common answer requirements

Locate competition-rank update and its initialization/change detector; explain dense distinct-score ranks with tied totals sharing rank and no skipped rank, preserving sort, names, averages and output.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Source evidence and minimization

Only the rank update changes to increment the distinct-total rank. Its initial value, change-of-total condition and previous-total update are needed. The indexed collection header supplies position, explaining current competition ranks. Sorting, averages and output remain unchanged.

Locations in main source: L8, L9, L10, L11, L12, L13.

All selected lines are complete, verbatim and in source order. The source evidence, the question, and documented language/library semantics support the answer. Inputs and branches unrelated to the answer are excluded. A modification-only question does not require unchanged implementation details solely to reconfirm the program remains correct. Imported library bindings are included when their contracts are used. Static types may replace inspection of user-defined implementations only for facts those types actually guarantee.

Alternative considered: the contiguous span between the first and last selected line and the full source. Those contain additional context, but do not reduce token cost. The selection is a reviewed sufficient candidate; exhaustive mathematical global minimality is not claimed.

Measurement: Task A 333; Task B 66. Tokenizer: metric/tokenizer.py, unchanged. Neither these lexical checks nor this selection establish execution/compilation of Task A.
