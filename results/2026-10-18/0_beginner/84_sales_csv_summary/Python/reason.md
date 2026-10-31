# Task B selection: 84_sales_csv_summary / Python

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.py`. Selected original locations: L1,L3,L5,L9,L10,L13,L15,L17,L18,L20,L21,L22,L23,L25,L26,L29,L31.

- L1: `from collections import Counter` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `rows = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    "2026-04-02,north,marker,8,150",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    "2026-04-02,east,notebook,9,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    "2026-04-03,north,eraser,20,80",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    "2026-04-04,south,notebook,6,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `regions, products, dates = Counter(), Counter(), Counter()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `for line in rows[1:]:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    date, region, product, quantity, price = line.split(",")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    quantity, price = int(quantity), int(price)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    sales = quantity * price` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    regions[region] += sales` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    products[product] += quantity` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `for region in sorted(regions, key=lambda name: (-regions[name], name)):` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `for product in sorted(products):` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **297 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 289 tokens. The contiguous original span L1–L31 costs 543 tokens; the complete original source costs 613 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 289 tokens; removes `from collections import Counter` from the dependency chain described above.
- Without L3: 291 tokens; removes `rows = [` from the dependency chain described above.
- Without L5: 271 tokens; removes `"2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L9: 272 tokens; removes `"2026-04-02,north,marker,8,150",` from the dependency chain described above.
- Without L10: 272 tokens; removes `"2026-04-02,east,notebook,9,200",` from the dependency chain described above.
- Without L13: 272 tokens; removes `"2026-04-03,north,eraser,20,80",` from the dependency chain described above.
- Without L15: 272 tokens; removes `"2026-04-04,south,notebook,6,200",` from the dependency chain described above.
- Without L17: 295 tokens; removes `]` from the dependency chain described above.
- Without L18: 273 tokens; removes `regions, products, dates = Counter(), Counter(), Counter()` from the dependency chain described above.
- Without L20: 285 tokens; removes `for line in rows[1:]:` from the dependency chain described above.
- Without L21: 271 tokens; removes `date, region, product, quantity, price = line.split(",")` from the dependency chain described above.
- Without L22: 278 tokens; removes `quantity, price = int(quantity), int(price)` from the dependency chain described above.
- Without L23: 286 tokens; removes `sales = quantity * price` from the dependency chain described above.
- Without L25: 287 tokens; removes `regions[region] += sales` from the dependency chain described above.
- Without L26: 287 tokens; removes `products[product] += quantity` from the dependency chain described above.
- Without L29: 266 tokens; removes `for region in sorted(regions, key=lambda name: (-regions[name], name)):` from the dependency chain described above.
- Without L31: 285 tokens; removes `for product in sorted(products):` from the dependency chain described above.
