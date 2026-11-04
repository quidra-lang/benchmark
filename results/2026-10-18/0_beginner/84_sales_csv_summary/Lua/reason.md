# Task B selection — 84_sales_csv_summary / Lua

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. The region comparator returns the larger total first, falling back to a < b for names; products use the default table.sort on the keys. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 1, 3, 7, 8, 11, 13, 16, 17, 18, 19, 20, 21, 22, 24, 25, 27, 29, 30, 31, 32, 33, 36, 37, 38, 39, 40, 42, 43.

With the benchmark tokenizer, this selection measures 498 tokens; the previous selection measured 500. The full source is 960 tokens.
