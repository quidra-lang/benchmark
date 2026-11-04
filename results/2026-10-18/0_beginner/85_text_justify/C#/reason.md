# Task B selection — 85_text_justify / C#

The retained guard separates the final or one-word line from full justification. Here j - 1 is the 0-based gap position, and the remainder test adds one space at the left. Leave the quotient and gap traversal as they are; change only the extra-space test so that this position is at least gap count minus remainder. Reversing the gap or word iteration would change more than the requested placement. Packing, right padding and framing need no changes.

Selected complete source lines: 29, 33, 35, 37, 39.

With the benchmark tokenizer, this selection measures 143 tokens; the previous selection measured 156. The full source is 666 tokens.
