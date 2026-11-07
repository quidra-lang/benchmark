# Task B selection: 00_array_mean / Quidra

## Common answer requirements

1. Identify the existing sum/mean and original-length denominator that must change.
2. Sum and count only elements at least 50; choose zero before division when that count is zero.
3. Leave the seven input values and existing single-line two-decimal presentation unchanged.

## Source evidence and minimization

The Core `values.mean()` call identifies both the input collection and the use of every element in its denominator. Filter the collection at this computation site, take the mean of the qualifying values, and choose zero when the filtered collection is empty. The literal data and the output statement need no changes; selecting either adds tokens without identifying another edit site.

Locations in main source: L2.

All selected lines are complete, verbatim and in source order. The source evidence, the question, and documented language/library semantics support the answer. Inputs and branches unrelated to the answer are excluded. A modification-only question does not require unchanged implementation details solely to reconfirm the program remains correct. Static types may replace inspection of user-defined implementations only for facts those types actually guarantee.

Alternative considered: the contiguous span between the first and last selected line and the full source. Those contain additional context, but do not reduce token cost. The selection is a reviewed sufficient candidate; exhaustive mathematical global minimality is not claimed.

Measurement: Task A 54; Task B 10. Tokenizer: metric/tokenizer.py, unchanged. Neither these lexical checks nor this selection establish execution/compilation of Task A.

## Current token measurement

Task A: **53 tokens**. Task B: **9 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
