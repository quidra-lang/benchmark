# Task B selection: 69_bowling_score / Quidra

## Answer requirements

Locate the cumulative score state and per-frame output; explain individual scores while retaining frame bonuses.

## Source evidence and supported analysis

Reset the score accumulator at the start of each frame, or record the prior cumulative total and print its difference. Existing scoring branches still include strike/spare bonuses from later rolls and add only the tenth frame's own remaining rolls. Keep one output per frame, game labels and single-space separators. Binding each game's rolls and index in the collection header changes only iteration boilerplate; the frame scorer is unchanged.

Selected complete `main.qui` lines: 12, 15, 27. Every excerpt line is copied verbatim in source order. Ordinary language and documented package semantics apply; the excerpt need not compile independently. User-defined behavior is supported by its selected operations, not by a helper name.

## Selection and measurement

The retained declarations, input values, control flow, calculations and change sites support the requested Task B answer. Unchanged unrelated processing and output are omitted. The complete source and the enclosing contiguous span are sufficient alternatives that add unrelated tokens. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Using unchanged `metric/tokenizer.py`: Task A **563** tokens; Task B **33** tokens. These measurements describe lexical source evidence; execution verification is recorded separately.
