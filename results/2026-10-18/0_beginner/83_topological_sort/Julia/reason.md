# Task B selection — 83_topological_sort / Julia

Search the ascending array with findlast instead of findfirst for the same untaken, zero-degree predicate. A missing candidate still yields nothing. The next choice still uses current eligibility, the empty selection still stops the loop, and the output format requires no edit. Graph construction and printing add no evidence about the selection change. The cycle list takes the set difference in the same ascending alphabetical order, so keep that input order.

Selected complete source lines: 10, 12, 13, 22.

With the benchmark tokenizer, this selection measures 63 tokens; the previous selection measured 60. The full source is 657 tokens.

## Current token measurement

Task A: **656 tokens**. Task B: **63 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
