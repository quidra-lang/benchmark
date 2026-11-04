# Task B selection — 84_sales_csv_summary / Java

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. The region comparator uses descending totals and natural name order for ties. The product TreeMap supplies keys in natural name order. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 10, 12, 16, 17, 20, 22, 24, 25, 26, 27, 28, 29, 31, 33, 34, 35, 39.

With the benchmark tokenizer, this selection measures 427 tokens; the previous selection measured 455. The full source is 1006 tokens.
