# Task B selection — 84_sales_csv_summary / Kotlin

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. The region comparator uses descending totals and ascending names for ties; sortedMapOf supplies ascending product keys. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 2, 4, 8, 9, 12, 14, 16, 17, 19, 20, 21, 22, 23, 24, 26, 28, 30.

With the benchmark tokenizer, this selection measures 386 tokens; the previous selection measured 412. The full source is 764 tokens.
