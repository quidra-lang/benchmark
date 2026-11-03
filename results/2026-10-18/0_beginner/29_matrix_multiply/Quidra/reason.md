# Task B selection: 29_matrix_multiply / Quidra

## Answer requirements

Read row one of A and column two of B, derive the four products and sum, and locate the second five-character field of the first output row.

## Source evidence and supported analysis

The gathered second column is [4,2,-1,7]; the first row of A is [3,-2,5,1]. Math dot computes 3*4 + (-2)*2 + 5*(-1) + 1*7 = 10 in index order. Nested row-then-column loops place that result in the second field of line one. Text pad_start applies a minimum total code-point width to the complete signed decimal string, yielding five characters including a minus sign when present. The typed string binding propagates padding errors. This preserves Task A's signed total-field width, which numeric integer-part padding alone cannot guarantee.

Selected complete `main.qui` lines: 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12. Every excerpt line is copied verbatim in source order. Ordinary language and documented package semantics apply; the excerpt need not compile independently. User-defined behavior is supported by its selected operations, not by a helper name.

## Selection and measurement

The retained declarations, input values, control flow, calculations and change sites support the requested Task B answer. Unchanged unrelated processing and output are omitted. The complete source and the enclosing contiguous span are sufficient alternatives that add unrelated tokens. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Using unchanged `metric/tokenizer.py`: Task A **208** tokens; Task B **207** tokens. These measurements describe lexical source evidence; execution verification is recorded separately.
