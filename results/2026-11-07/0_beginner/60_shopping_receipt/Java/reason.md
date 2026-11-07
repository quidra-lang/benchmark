# Task B selection: 60_shopping_receipt / Java

Food subtotals are milk 396, bread 248, apple 512 and eggs 268, totaling 1424. Integer division after aggregation gives food tax 1424*8/100 = 113; per-item truncation would sum to 111. General subtotal is 932 and tax 93. The final payment adds both untaxed subtotals and each category tax exactly once, totaling 2562.

Keep item/category data, subtotal accumulation, category tax division and final addition. Per-item and per-category presentation lines do not determine the truncation dependency.

Selected complete source lines in `Main.java`: 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17, 20. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
