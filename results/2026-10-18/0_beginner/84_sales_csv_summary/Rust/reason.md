# Task B selection — 84_sales_csv_summary / Rust

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. The region comparison reverses the totals and then compares names normally; the product BTreeMap iterator yields ascending keys. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 4, 6, 10, 11, 14, 16, 19, 21, 22, 23, 24, 25, 27, 28, 30, 31, 32, 37.

With the benchmark tokenizer, this selection measures 438 tokens; the previous selection measured 442. The full source is 877 tokens.
