# Task B selection: 24_word_stats / Go

Choose the last sentence occurrence independently for each extreme length. Leave the sentence, count, average, and output structure alone.

range visits the word slice in increasing index order. Make the longest comparison greater-than-or-equal and the shortest comparison less-than-or-equal, preserving their separate assignments.

Complete main.go lines: 11, 13, 14, 16, 17. A comparison against an undefined length or an unexplained scan order would omit a tie-selection dependency. Initialization that remains guarded and the unaffected count/average formatting are outside the edit. The benchmark tokenizer counts 70 tokens in this excerpt.

## Current token measurement

Task A: **254 tokens**. Task B: **70 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
