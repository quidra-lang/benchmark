# Task B selection — 84_sales_csv_summary / JavaScript

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. The region comparator subtracts totals in reverse order and calls alphabetical on ties; the product sort uses ascending string order. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 1, 3, 5, 7, 8, 10, 12, 13, 14, 16, 17, 19, 20, 21, 24.

With the benchmark tokenizer, this selection measures 518 tokens; the previous selection measured 521. The full source is 817 tokens.
