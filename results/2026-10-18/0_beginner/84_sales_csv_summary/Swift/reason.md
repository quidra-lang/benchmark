# Task B selection — 84_sales_csv_summary / Swift

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. The region comparator orders differing totals descending and equal totals by ascending name; products sort their names ascending. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 1, 3, 7, 8, 11, 13, 15, 16, 17, 18, 19, 20, 22, 24, 26.

With the benchmark tokenizer, this selection measures 390 tokens; the previous selection measured 415. The full source is 742 tokens.
