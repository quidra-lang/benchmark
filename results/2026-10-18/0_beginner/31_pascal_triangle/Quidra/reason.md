# Task B selection: 31_pascal_triangle / Quidra

## Common answer requirements

[Code comprehension]

Using the source code, trace how row 4 of Pascal's triangle is produced from row 3, where row 0 is the first row. Explain the origin of both endpoint values and each interior value, identifying the source operations that combine neighboring values from the preceding row. Derive the complete line printed for row 4.

## Source evidence and minimization

The initial row and one-element zero array, loop bound and componentwise sum of the two shifted rows establish every endpoint and interior term. The print precedes the update, so row 0 is printed first. Text join preserves array order and inserts one space without a trailing separator; its documented contract replaces the removed conversion comprehension.

Locations in main source: L1, L3, L4, L5, L6, L7.

The selected lines are complete, verbatim and in source order. Library semantics are used only with the required binding/type evidence. A separate pass checked that the excerpt supports each requested fact; unrelated output or unchanged implementations are excluded. Replacing this selection with the full enclosing span or whole source adds tokens without adding necessary answer evidence. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Measurement: Task A 75; Task B 74. Tokenizer: metric/tokenizer.py, unchanged. These source-token checks do not establish compilation or execution of Task A.
