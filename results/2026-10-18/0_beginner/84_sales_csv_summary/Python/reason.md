# Task B selection — 84_sales_csv_summary / Python

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. The region key is negative total followed by name, while the product keys use plain ascending sorted. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 1, 3, 5, 9, 10, 13, 15, 18, 20, 21, 22, 23, 25, 26, 29, 31.

With the benchmark tokenizer, this selection measures 295 tokens; the previous selection measured 313. The full source is 613 tokens.

## Current token measurement

Task A: **610 tokens**. Task B: **292 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
