# Task B selection — 83_topological_sort / R

Take the last entry of the current eligible vector rather than its first. Leave the ascending source vector alone because its untaken subsequence also supplies the cycle list. The next choice still uses current eligibility, the empty selection still stops the loop, and the output format requires no edit. Graph construction and printing add no evidence about the selection change.

Selected complete source lines: 9, 11, 13, 17.

With the benchmark tokenizer, this selection measures 80 tokens; the previous selection measured 55. The full source is 741 tokens.
