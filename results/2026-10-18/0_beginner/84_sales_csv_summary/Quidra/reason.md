# Task B selection — 84_sales_csv_summary / Quidra

The retained north rows contribute 10×200, 8×150 and 20×80, totaling 4,800. The notebook rows contribute 10, 9 and 6 units, totaling 25. The parsing and accumulators distinguish quantity×price grouped by region from quantity alone grouped by product. The collections contracts give ranked_entries descending value with ascending key ties, while sorted_entries uses ascending key alone. Separate rows that belong to neither group, list terminators, and overall/date totals are unnecessary for these traces.

Selected complete source lines: 1, 3, 5, 9, 10, 13, 15, 18, 19, 22, 23, 24, 25, 26, 28, 29, 32, 34.

With the benchmark tokenizer, this selection measures 310 tokens; the previous selection measured 326. The full source is 627 tokens.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 627; Task B 310.
