# Task B selection — 84_sales_csv_summary / Dart

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. Region sort compares the values in descending order and then the names ascending. Product names use the default ascending String sort. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 2, 4, 8, 9, 12, 14, 17, 18, 21, 22, 23, 24, 26, 27, 29, 30, 31, 32, 33, 34, 35.

With the benchmark tokenizer, this selection measures 411 tokens; the previous selection measured 415. The full source is 860 tokens.
