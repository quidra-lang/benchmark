# Task B selection: 22_char_frequency / Go

Count uppercase and lowercase ASCII letters separately, ignore other characters, and print only present letters in uppercase-then-lowercase order with their original case and line format.

Remove the ASCII lowercase conversion, map the two accepted ranges into 52 array slots, and reconstruct their characters in index order. Retain the positive-count guard.

Complete main.go lines: 7, 9, 10, 11, 12, 13, 16, 17, 18. Retain the folding, eligibility, counter and output evidence rather than inferring case, ordering or sparsity from a variable name. Unchanged setup and source text are unnecessary unless a complete line combines them with a necessary operation. The benchmark tokenizer counts 156 tokens in this excerpt.

## Current token measurement

Task A: **231 tokens**. Task B: **156 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
