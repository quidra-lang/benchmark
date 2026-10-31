# Task B selection: 84_sales_csv_summary / J

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.ijs`. Selected original locations: L1,L2,L3,L6,L7,L8,L9,L10,L12,L13,L14,L15,L16,L17,L18,L20,L21,L22,L23,L24,L25.

- L1: `split =: 4 : 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  <;._1 x,y` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `)` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L6: `  csv =. 'date,region,product,quantity,unit_price';'2026-04-01,north,notebook,10,200';'2026-04-01,east,marker,6,150';'2026-04-01,south,eraser,25,80';'2026-04-02,west,stapler,4,600';'2026-04-02,north,marker,8,150';'2026-04-02,east,notebook,9,200';'2026-04-03,south,stapler,3,600';'2026-04-03,west,eraser,15,80';'2026-04-03,north,eraser,20,80';'2026-04-04,east,stapler,5,600';'2026-04-04,south,notebook,6,200';'2026-04-04,west,marker,8,150'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  dates =. regions =. products =. 0$<''` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `  quantities =. amounts =. i.0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `  for_line. }.csv do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    fields =. ',' split >line` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    regions =. regions,1{fields` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    products =. products,2{fields` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    quantity =. 0".>3{fields` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    price =. 0".>4{fields` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    quantities =. quantities,quantity` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    amounts =. amounts,quantity*price` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `  end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `  names =. /:~ ~.regions` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `  totals =. i.0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `  for_name. names do. totals =. totals,+/(regions=name)#amounts end.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `  for_i. \:totals do. smoutput (>i{names),': ',":i{totals end.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `  for_name. /:~ ~.products do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    smoutput (>name),': ',":+/(products=name)#quantities` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **562 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 557 tokens. The contiguous original span L1–L25 costs 599 tokens; the complete original source costs 704 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 552 tokens; removes `split =: 4 : 0` from the dependency chain described above.
- Without L2: 552 tokens; removes `<;._1 x,y` from the dependency chain described above.
- Without L3: 560 tokens; removes `)` from the dependency chain described above.
- Without L6: 266 tokens; removes `csv =. 'date,region,product,quantity,unit_price';'2026-04-01,north,notebook,10,200';'2026-04-01,east,marker,6,150';'2026-04-01,south,eraser,25,80';'2026-04-02,west,stapler,4,600';'2026-04-02,north,marker,8,150';'2026-04-02,east,notebook,9,200';'2026-04-03,south,stapler,3,600';'2026-04-03,west,eraser,15,80';'2026-04-03,north,eraser,20,80';'2026-04-04,east,stapler,5,600';'2026-04-04,south,notebook,6,200';'2026-04-04,west,marker,8,150'` from the dependency chain described above.
- Without L7: 543 tokens; removes `dates =. regions =. products =. 0$<''` from the dependency chain described above.
- Without L8: 550 tokens; removes `quantities =. amounts =. i.0` from the dependency chain described above.
- Without L9: 551 tokens; removes `for_line. }.csv do.` from the dependency chain described above.
- Without L10: 548 tokens; removes `fields =. ',' split >line` from the dependency chain described above.
- Without L12: 551 tokens; removes `regions =. regions,1{fields` from the dependency chain described above.
- Without L13: 551 tokens; removes `products =. products,2{fields` from the dependency chain described above.
- Without L14: 550 tokens; removes `quantity =. 0".>3{fields` from the dependency chain described above.
- Without L15: 550 tokens; removes `price =. 0".>4{fields` from the dependency chain described above.
- Without L16: 553 tokens; removes `quantities =. quantities,quantity` from the dependency chain described above.
- Without L17: 551 tokens; removes `amounts =. amounts,quantity*price` from the dependency chain described above.
- Without L18: 559 tokens; removes `end.` from the dependency chain described above.
- Without L20: 551 tokens; removes `names =. /:~ ~.regions` from the dependency chain described above.
- Without L21: 554 tokens; removes `totals =. i.0` from the dependency chain described above.
- Without L22: 534 tokens; removes `for_name. names do. totals =. totals,+/(regions=name)#amounts end.` from the dependency chain described above.
- Without L23: 529 tokens; removes `for_i. \:totals do. smoutput (>i{names),': ',":i{totals end.` from the dependency chain described above.
- Without L24: 548 tokens; removes `for_name. /:~ ~.products do.` from the dependency chain described above.
- Without L25: 537 tokens; removes `smoutput (>name),': ',":+/(products=name)#quantities` from the dependency chain described above.
