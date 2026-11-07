# Task B selection — 85_text_justify / Rust

The retained guard separates the final or one-word line from full justification. Here i - start is the 0-based gap position, and the remainder test adds one space at the left. Leave the quotient and gap traversal as they are; change only the extra-space test so that this position is at least gap count minus remainder. Reversing the gap or word iteration would change more than the requested placement. Packing, right padding and framing need no changes.

Selected complete source lines: 11, 12, 14, 16, 17, 19, 20.

With the benchmark tokenizer, this selection measures 149 tokens; the previous selection measured 132. The full source is 586 tokens.

## Current token measurement

Task A: **577 tokens**. Task B: **148 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
