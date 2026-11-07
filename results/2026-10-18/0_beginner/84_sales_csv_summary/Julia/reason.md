# Task B selection — 84_sales_csv_summary / Julia

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. The region sort uses the tuple of negated total and name; the product sort uses only its keys. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 2, 4, 8, 9, 12, 14, 17, 19, 20, 21, 22, 24, 25, 27, 29, 31, 32.

With the benchmark tokenizer, this selection measures 370 tokens; the previous selection measured 373. The full source is 737 tokens.

## Current token measurement

Task A: **732 tokens**. Task B: **367 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
