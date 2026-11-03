# Task B selection: 84_sales_csv_summary / Ruby

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.rb`. Selected original locations: L1,L3,L5,L7,L8,L9,L10,L12,L13,L14,L15,L17,L18,L20,L22,L23.

- L1: `rows = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  '2026-04-01,north,notebook,10,200', '2026-04-01,east,marker,6,150',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  '2026-04-02,north,marker,8,150', '2026-04-02,east,notebook,9,200',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  '2026-04-03,north,eraser,20,80', '2026-04-04,east,stapler,5,600',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `  '2026-04-04,south,notebook,6,200', '2026-04-04,west,marker,8,150'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L10: `regions, products, dates = Hash.new(0), Hash.new(0), Hash.new(0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `rows.drop(1).each do |line|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `  date, region, product, quantity, price = line.split(',')` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `  quantity, price = quantity.to_i, price.to_i` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `  sales = quantity * price` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `  regions[region] += sales` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `  products[product] += quantity` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `regions.keys.sort_by { |name| [-regions[name], name] }.each { |name| puts "#{name}: #{regions[name]}" }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `products.keys.sort.each { |name| puts "#{name}: #{products[name]}" }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **418 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 408 tokens. The contiguous original span L1–L23 costs 567 tokens; the complete original source costs 622 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 412 tokens; removes `rows = [` from the dependency chain described above.
- Without L3: 368 tokens; removes `'2026-04-01,north,notebook,10,200', '2026-04-01,east,marker,6,150',` from the dependency chain described above.
- Without L5: 369 tokens; removes `'2026-04-02,north,marker,8,150', '2026-04-02,east,notebook,9,200',` from the dependency chain described above.
- Without L7: 369 tokens; removes `'2026-04-03,north,eraser,20,80', '2026-04-04,east,stapler,5,600',` from the dependency chain described above.
- Without L8: 370 tokens; removes `'2026-04-04,south,notebook,6,200', '2026-04-04,west,marker,8,150'` from the dependency chain described above.
- Without L9: 416 tokens; removes `]` from the dependency chain described above.
- Without L10: 385 tokens; removes `regions, products, dates = Hash.new(0), Hash.new(0), Hash.new(0)` from the dependency chain described above.
- Without L12: 403 tokens; removes `rows.drop(1).each do |line|` from the dependency chain described above.
- Without L13: 392 tokens; removes `date, region, product, quantity, price = line.split(',')` from the dependency chain described above.
- Without L14: 397 tokens; removes `quantity, price = quantity.to_i, price.to_i` from the dependency chain described above.
- Without L15: 407 tokens; removes `sales = quantity * price` from the dependency chain described above.
- Without L17: 408 tokens; removes `regions[region] += sales` from the dependency chain described above.
- Without L18: 408 tokens; removes `products[product] += quantity` from the dependency chain described above.
- Without L20: 416 tokens; removes `end` from the dependency chain described above.
- Without L22: 365 tokens; removes `regions.keys.sort_by { |name| [-regions[name], name] }.each { |name| puts "#{name}: #{regions[name]}" }` from the dependency chain described above.
- Without L23: 385 tokens; removes `products.keys.sort.each { |name| puts "#{name}: #{products[name]}" }` from the dependency chain described above.
