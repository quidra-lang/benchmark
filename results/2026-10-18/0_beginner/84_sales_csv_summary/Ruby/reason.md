# Task B selection — 84_sales_csv_summary / Ruby

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. The region sort uses the array of negative total and name, while products sort just the names. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 1, 3, 5, 7, 8, 10, 12, 13, 14, 15, 17, 18, 20, 22, 23.

With the benchmark tokenizer, this selection measures 416 tokens; the previous selection measured 418. The full source is 622 tokens.
