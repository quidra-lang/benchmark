# Task B selection: 35_statistics_summary / Python

## Common answer requirements

Identify the standard-deviation denominator and change only that normalization from n=11 to n−1=10 before the square root. Preserve the mean, ordered squared-difference accumulation, stdev label, three-decimal half-up presentation and every other statistic.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Source evidence and minimization

Retain the existing question-specific semantic selection, and add the actual import binding for each selected standard-library call. For the CSV trace, include the header to explain the data slice offset. These are required source facts, not additional implementation inspection.

Locations in main source: L1, L10.

All selected lines are complete, verbatim and in source order. The source evidence, the question, and documented language/library semantics support the answer. Inputs and branches unrelated to the answer are excluded. A modification-only question does not require unchanged implementation details solely to reconfirm the program remains correct. Imported library bindings are included when their contracts are used. Static types may replace inspection of user-defined implementations only for facts those types actually guarantee.

Alternative considered: the contiguous span between the first and last selected line and the full source. Those contain additional context, but do not reduce token cost. The selection is a reviewed sufficient candidate; exhaustive mathematical global minimality is not claimed.

Measurement: Task A 245; Task B 24. Tokenizer: metric/tokenizer.py, unchanged. Neither these lexical checks nor this selection establish execution/compilation of Task A.
