# Task B selection — 85_text_justify / C++

The retained guard separates the final or one-word line from full justification. Here i - start is the 0-based gap position, and the remainder test adds one space at the left. Leave the quotient and gap traversal as they are; change only the extra-space test so that this position is at least gap count minus remainder. Reversing the gap or word iteration would change more than the requested placement. Packing, right padding and framing need no changes.

Selected complete source lines: 18, 19, 21, 23, 24, 25.

With the benchmark tokenizer, this selection measures 166 tokens; the previous selection measured 135. The full source is 630 tokens.
