# Task B selection — 83_topological_sort / Kotlin

Use lastOrNull instead of firstOrNull for the current eligibility predicate. The same sorted names list feeds the cycle filter and must stay ascending. The next choice still uses current eligibility, the empty selection still stops the loop, and the output format requires no edit. Graph construction and printing add no evidence about the selection change.

Selected complete source lines: 2, 15, 24.

With the benchmark tokenizer, this selection measures 84 tokens; the previous selection measured 66. The full source is 728 tokens.

## Current token measurement

Task A: **725 tokens**. Task B: **83 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
