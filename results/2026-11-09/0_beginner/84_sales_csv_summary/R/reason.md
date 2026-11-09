# Task B: 84_sales_csv_summary / R

Convert the quantity token `"10"` to exact integer value 10 before amount=quantity×price and before product quantity totals. Current source already performs that runtime conversion; a string literal is not multiplied or accumulated as quantity. Date, region and product stay textual. Sales amount feeds monetary totals/region/day aggregation, while quantity feeds the separate product count aggregation. Small exact values do not imply every binding has a static integer type.

as.integer(fields[4]) establishes quantity; as.integer(fields[5]) establishes price. Other fields remain character, and separate accumulators receive amount or quantity.

Evidence is from `main.R`, L16,L17,L18,L19,L20,L21.

- L16: `fields <- do.call(rbind, strsplit(lines[-1], ",", fixed = TRUE))`
- L17: `quantities <- as.integer(fields[, 4])`
- L18: `amounts <- quantities * as.integer(fields[, 5])`
- L19: `regions <- tapply(amounts, fields[, 2], sum)`
- L20: `products <- tapply(quantities, fields[, 3], sum)`
- L21: `days <- tapply(amounts, fields[, 1], sum)`

Minimization: The split-field bindings, numeric conversions, named amount and both monetary/quantity accumulation paths are necessary. CSV parser internals and final report formatting are outside this local type-contract question. The selected complete original lines, in source order, cost 129 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 129, and the complete source costs 635. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
