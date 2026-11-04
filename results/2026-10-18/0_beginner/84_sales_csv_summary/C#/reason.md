# Task B selection — 84_sales_csv_summary / C#

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. OrderByDescending sorts by sale amount and ThenBy uses ordinal name for ties. SortedDictionary already enumerates products by ordinal name. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 8, 10, 14, 15, 18, 20, 22, 23, 25, 26, 27, 28, 29, 30, 31, 33, 35, 39.

With the benchmark tokenizer, this selection measures 404 tokens; the previous selection measured 435. The full source is 817 tokens.
