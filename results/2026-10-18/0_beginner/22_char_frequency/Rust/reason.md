# Task B selection: 22_char_frequency / Rust

Count uppercase and lowercase ASCII letters separately, ignore other characters, and print only present letters in uppercase-then-lowercase order with their original case and line format.

The input bytes are converted to lowercase and tallied in 26 slots. Use 52 slots and range-specific indexing, then reconstruct the original character in the index-order iteration. Keep the positive-count test and existing separators.

Complete main.rs lines: 3, 4, 5, 6, 7, 10, 11, 12. Retain the folding, eligibility, counter and output evidence rather than inferring case, ordering or sparsity from a variable name. Unchanged setup and source text are unnecessary unless a complete line combines them with a necessary operation. The benchmark tokenizer counts 170 tokens in this excerpt.

## Current token measurement

Task A: **215 tokens**. Task B: **165 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
