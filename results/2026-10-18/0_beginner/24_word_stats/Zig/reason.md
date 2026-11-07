# Task B selection: 24_word_stats / Zig

Choose the last sentence occurrence independently for each extreme length. Leave the sentence, count, average, and output structure alone.

next() advances through the words in order. Widen the two strict length comparisons to include equality, leaving the count-zero initialization checks untouched.

Complete main.zig lines: 12, 13, 14, 15, 16. A comparison against an undefined length or an unexplained scan order would omit a tie-selection dependency. Initialization that remains guarded and the unaffected count/average formatting are outside the edit. The benchmark tokenizer counts 85 tokens in this excerpt.

## Current token measurement

Task A: **436 tokens**. Task B: **84 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
