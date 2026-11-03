# Task B selection: 73_merge_sort_inversions / Quidra

## Answer requirements

Locate the shared inversion state and merge-trace output; append the cumulative count after each completed merge.

## Source evidence and supported analysis

The reference parameter, initial zero, both recursive calls using the same reference and the right-side increment establish a cumulative count across all completed merges. Append the current `inversions` value to the selected merge print before its newline. The slice assignment writes the completed merged range back exactly as the prior indexed copy loop did. Final sorted and inversion-summary lines need no change; their unchanged details are outside this modification excerpt.

Selected complete `main.qui` lines: 1, 3, 4, 5, 6, 7, 8, 21, 24, 27, 28. Every excerpt line is copied verbatim in source order. Ordinary language and documented package semantics apply; the excerpt need not compile independently. User-defined behavior is supported by its selected operations, not by a helper name.

## Selection and measurement

The retained declarations, input values, control flow, calculations and change sites support the requested Task B answer. Unchanged unrelated processing and output are omitted. The complete source and the enclosing contiguous span are sufficient alternatives that add unrelated tokens. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Using unchanged `metric/tokenizer.py`: Task A **468** tokens; Task B **186** tokens. These measurements describe lexical source evidence; execution verification is recorded separately.
