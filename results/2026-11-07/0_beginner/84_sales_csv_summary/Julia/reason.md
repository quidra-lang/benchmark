# Task B: 84_sales_csv_summary / Julia

Convert the quantity token `"10"` to exact integer value 10 before amount=quantity×price and before product quantity totals. Current source already performs that runtime conversion; a string literal is not multiplied or accumulated as quantity. Date, region and product stay textual. Sales amount feeds monetary totals/region/day aggregation, while quantity feeds the separate product count aggregation. Small exact values do not imply every binding has a static integer type.

parse(Int,quantity_text) and parse(Int,price_text) produce Int operands. Dict aggregates distinguish amount from quantity; local variable names themselves are not explicit type annotations.

Evidence is from `main.jl`, L20,L21,L22,L23,L24,L25,L26.

- L20: `date, region, product, quantity_text, price_text = split(line, ',')`
- L21: `quantity, price = parse(Int, quantity_text), parse(Int, price_text)`
- L22: `amount = quantity*price`
- L23: `total += amount`
- L24: `regions[region] = get(regions, region, 0)+amount`
- L25: `products[product] = get(products, product, 0)+quantity`
- L26: `days[date] = get(days, date, 0)+amount`

Minimization: The split-field bindings, numeric conversions, named amount and both monetary/quantity accumulation paths are necessary. CSV parser internals and final report formatting are outside this local type-contract question. The selected complete original lines, in source order, cost 146 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 146, and the complete source costs 732. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
