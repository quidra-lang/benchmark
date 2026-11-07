# Task B selection: 22_char_frequency / JavaScript

Count uppercase and lowercase ASCII letters separately, ignore other characters, and print only present letters in uppercase-then-lowercase order with their original case and line format.

The Map starts empty and is populated from lowercase letters only. Count original ASCII letters from both ranges as separate keys; default sorting of the one-character ASCII keys puts uppercase first. Only stored keys are printed, without case conversion.

Complete main.js lines: 2, 3, 4, 6. Retain the folding, eligibility, counter and output evidence rather than inferring case, ordering or sparsity from a variable name. Unchanged setup and source text are unnecessary unless a complete line combines them with a necessary operation. The benchmark tokenizer counts 127 tokens in this excerpt.

## Current token measurement

Task A: **151 tokens**. Task B: **123 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
