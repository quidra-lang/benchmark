# Task B selection: 22_char_frequency / Java

Count uppercase and lowercase ASCII letters separately, ignore other characters, and print only present letters in uppercase-then-lowercase order with their original case and line format.

Lowercasing and indexing into 26 slots merges case. Use 52 slots for the two allowed ranges and reconstruct the letter using the same mapping in the ascending loop. Keep the positive guard.

Complete Main.java lines: 5, 7, 8, 9, 12, 13, 14. Retain the folding, eligibility, counter and output evidence rather than inferring case, ordering or sparsity from a variable name. Unchanged setup and source text are unnecessary unless a complete line combines them with a necessary operation. The benchmark tokenizer counts 178 tokens in this excerpt.

## Current token measurement

Task A: **263 tokens**. Task B: **177 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
