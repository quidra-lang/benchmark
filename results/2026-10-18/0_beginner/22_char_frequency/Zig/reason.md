# Task B selection: 22_char_frequency / Zig

Count uppercase and lowercase ASCII letters separately, ignore other characters, and print only present letters in uppercase-then-lowercase order with their original case and line format.

The ASCII lowercase call and 26-slot storage merge case; instead accept either ASCII range and use 52 slots ordered by case, then reconstruct the matching letter when printing. Preserve the positive guard.

Complete main.zig lines: 8, 10, 11, 12, 14, 15, 16. Retain the folding, eligibility, counter and output evidence rather than inferring case, ordering or sparsity from a variable name. Unchanged setup and source text are unnecessary unless a complete line combines them with a necessary operation. The benchmark tokenizer counts 167 tokens in this excerpt.

## Current token measurement

Task A: **326 tokens**. Task B: **167 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
