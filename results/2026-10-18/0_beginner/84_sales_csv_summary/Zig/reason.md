# Task B selection — 84_sales_csv_summary / Zig

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. salesLess places higher totals first and delegates ties to nameLess, while the product sort directly uses nameLess. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 18, 20, 21, 22, 28, 30, 34, 35, 38, 40, 43, 44, 46, 47, 50, 51, 52, 53, 54, 55, 56, 57, 59, 60, 62, 63, 64.

With the benchmark tokenizer, this selection measures 752 tokens; the previous selection measured 756. The full source is 1387 tokens.
