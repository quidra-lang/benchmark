# Task B: 84_sales_csv_summary / J

Convert the quantity token `"10"` to exact integer value 10 before amount=quantity×price and before product quantity totals. Current source already performs that runtime conversion; a string literal is not multiplied or accumulated as quantity. Date, region and product stay textual. Sales amount feeds monetary totals/region/day aggregation, while quantity feeds the separate product count aggregation. Small exact values do not imply every binding has a static integer type.

0". parses quantity and price; the named amount is their product. Numeric conversion is a runtime operation, while the fields copied into dates/regions/products remain text values.

Evidence is from `main.ijs`, L10,L11,L12,L13,L14,L15,L16,L17,L18,L20,L21,L22,L23,L25,L26,L28,L29,L30.

- L10: `fields =. ',' split >line`
- L11: `dates =. dates,0{fields`
- L12: `regions =. regions,1{fields`
- L13: `products =. products,2{fields`
- L14: `quantity =. 0".>3{fields`
- L15: `price =. 0".>4{fields`
- L16: `quantities =. quantities,quantity`
- L17: `amount =. quantity*price`
- L18: `amounts =. amounts,amount`
- L20: `smoutput 'total: ',":+/amounts`
- L21: `names =. /:~ ~.regions`
- L22: `totals =. i.0`
- L23: `for_name. names do. totals =. totals,+/(regions=name)#amounts end.`
- L25: `for_name. /:~ ~.products do.`
- L26: `smoutput (>name),': ',":+/(products=name)#quantities`
- L28: `days =. /:~ ~.dates`
- L29: `totals =. i.0`
- L30: `for_day. days do. totals =. totals,+/(dates=day)#amounts end.`

Minimization: The split-field bindings, numeric conversions, named amount and both monetary/quantity accumulation paths are necessary. CSV parser internals and final report formatting are outside this local type-contract question. The selected complete original lines, in source order, cost 246 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 285, and the complete source costs 711. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
