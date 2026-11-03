# Task B selection: 84_sales_csv_summary / Julia

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.jl`. Selected original locations: L2,L4,L8,L9,L12,L14,L16,L17,L19,L20,L21,L22,L24,L25,L27,L29,L31,L32.

- L2: `    lines = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `        "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `        "2026-04-02,north,marker,8,150",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        "2026-04-02,east,notebook,9,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        "2026-04-03,north,eraser,20,80",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        "2026-04-04,south,notebook,6,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    ]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `    regions, products, days = Dict{String,Int}(), Dict{String,Int}(), Dict{String,Int}()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    for line in lines[2:end]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        date, region, product, quantity_text, price_text = split(line, ',')` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        quantity, price = parse(Int, quantity_text), parse(Int, price_text)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        amount = quantity*price` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        regions[region] = get(regions, region, 0)+amount` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        products[product] = get(products, product, 0)+quantity` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `    for region in sort(collect(keys(regions)); by = region -> (-regions[region], region))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `    for product in sort(collect(keys(products)))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **373 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 357 tokens. The contiguous original span L2–L32 costs 641 tokens; the complete original source costs 737 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L2: 366 tokens; removes `lines = [` from the dependency chain described above.
- Without L4: 346 tokens; removes `"2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L8: 347 tokens; removes `"2026-04-02,north,marker,8,150",` from the dependency chain described above.
- Without L9: 347 tokens; removes `"2026-04-02,east,notebook,9,200",` from the dependency chain described above.
- Without L12: 347 tokens; removes `"2026-04-03,north,eraser,20,80",` from the dependency chain described above.
- Without L14: 347 tokens; removes `"2026-04-04,south,notebook,6,200",` from the dependency chain described above.
- Without L16: 370 tokens; removes `]` from the dependency chain described above.
- Without L17: 333 tokens; removes `regions, products, days = Dict{String,Int}(), Dict{String,Int}(), Dict{String,Int}()` from the dependency chain described above.
- Without L19: 359 tokens; removes `for line in lines[2:end]` from the dependency chain described above.
- Without L20: 341 tokens; removes `date, region, product, quantity_text, price_text = split(line, ',')` from the dependency chain described above.
- Without L21: 343 tokens; removes `quantity, price = parse(Int, quantity_text), parse(Int, price_text)` from the dependency chain described above.
- Without L22: 363 tokens; removes `amount = quantity*price` from the dependency chain described above.
- Without L24: 351 tokens; removes `regions[region] = get(regions, region, 0)+amount` from the dependency chain described above.
- Without L25: 351 tokens; removes `products[product] = get(products, product, 0)+quantity` from the dependency chain described above.
- Without L27: 370 tokens; removes `end` from the dependency chain described above.
- Without L29: 335 tokens; removes `for region in sort(collect(keys(regions)); by = region -> (-regions[region], region))` from the dependency chain described above.
- Without L31: 370 tokens; removes `end` from the dependency chain described above.
- Without L32: 355 tokens; removes `for product in sort(collect(keys(products)))` from the dependency chain described above.
