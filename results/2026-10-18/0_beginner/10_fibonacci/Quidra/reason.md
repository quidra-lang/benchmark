# Task B selection: 10_fibonacci / Quidra

## Answer requirements

Locate the inclusive term limit and the integer state; keep every generated term and the total exact for forty terms.

## Source evidence and supported analysis

Change the loop bound from 30 to 40. The total update belongs to the same inclusive term loop, so extending that loop extends its sum as well. The only three integer state bindings are explicit; the unchanged simultaneous recurrence introduces no separately typed intermediate that could overflow. `int` is arbitrary precision; F(40)=102334155 and the forty-term sum is 267914295 remain exact. Spacing and the final sum label need no change.

Selected complete `main.qui` lines: 1, 2, 3, 4, 8. Every excerpt line is copied verbatim in source order. Ordinary language and documented package semantics apply; the excerpt need not compile independently. User-defined behavior is supported by its selected operations, not by a helper name.

## Selection and measurement

The retained declarations, input values, control flow, calculations and change sites support the requested Task B answer. Unchanged unrelated processing and output are omitted. The complete source and the enclosing contiguous span are sufficient alternatives that add unrelated tokens. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Using unchanged `metric/tokenizer.py`: Task A **108** tokens; Task B **46** tokens. These measurements describe lexical source evidence; execution verification is recorded separately.
