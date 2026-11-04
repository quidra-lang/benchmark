# Task B selection — 84_sales_csv_summary / R

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. Region order uses the negated totals and names as sort keys; products use only sorted names. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 1, 3, 7, 8, 11, 13, 16, 17, 18, 19, 20, 23, 24.

With the benchmark tokenizer, this selection measures 352 tokens; the previous selection measured 354. The full source is 635 tokens.
