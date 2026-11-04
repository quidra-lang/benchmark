# Task B selection — 84_sales_csv_summary / PHP

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. The region comparator uses the descending spaceship comparison on totals and strcmp for ties; product keys use ksort with SORT_STRING. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 3, 5, 9, 10, 13, 15, 18, 20, 21, 22, 23, 24, 26, 27, 29, 31, 32, 36, 37.

With the benchmark tokenizer, this selection measures 409 tokens; the previous selection measured 412. The full source is 844 tokens.
