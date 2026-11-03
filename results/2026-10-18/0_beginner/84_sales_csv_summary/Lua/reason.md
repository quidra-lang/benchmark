# Task B selection: 84_sales_csv_summary / Lua

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.lua`. Selected original locations: L1,L3,L7,L8,L11,L13,L15,L16,L17,L18,L19,L20,L21,L22,L24,L25,L27,L29,L30,L31,L32,L33,L36,L37,L38,L39,L40,L42,L43.

- L1: `local lines = {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    "2026-04-02,north,marker,8,150",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    "2026-04-02,east,notebook,9,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    "2026-04-03,north,eraser,20,80",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    "2026-04-04,south,notebook,6,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `local regions, products, days, total = {}, {}, {}, 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `for i = 2, #lines do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    local fields = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    for field in lines[i]:gmatch("[^,]+") do fields[#fields + 1] = field end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    local date, region, product = fields[1], fields[2], fields[3]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    local quantity, price = tonumber(fields[4]), tonumber(fields[5])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    local amount = quantity * price` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    regions[region] = (regions[region] or 0) + amount` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    products[product] = (products[product] or 0) + quantity` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `local function keys(values)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    local result = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    for key in pairs(values) do result[#result + 1] = key end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    return result` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L36: `local region_names = keys(regions)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `table.sort(region_names, function(a, b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    if regions[a] ~= regions[b] then return regions[a] > regions[b] end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    return a < b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `end)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `local product_names = keys(products)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `table.sort(product_names)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **500 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 483 tokens. The contiguous original span L1–L43 costs 799 tokens; the complete original source costs 960 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 492 tokens; removes `local lines = {` from the dependency chain described above.
- Without L3: 474 tokens; removes `"2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L7: 475 tokens; removes `"2026-04-02,north,marker,8,150",` from the dependency chain described above.
- Without L8: 475 tokens; removes `"2026-04-02,east,notebook,9,200",` from the dependency chain described above.
- Without L11: 475 tokens; removes `"2026-04-03,north,eraser,20,80",` from the dependency chain described above.
- Without L13: 475 tokens; removes `"2026-04-04,south,notebook,6,200",` from the dependency chain described above.
- Without L15: 498 tokens; removes `}` from the dependency chain described above.
- Without L16: 471 tokens; removes `local regions, products, days, total = {}, {}, {}, 0` from the dependency chain described above.
- Without L17: 486 tokens; removes `for i = 2, #lines do` from the dependency chain described above.
- Without L18: 490 tokens; removes `local fields = {}` from the dependency chain described above.
- Without L19: 460 tokens; removes `for field in lines[i]:gmatch("[^,]+") do fields[#fields + 1] = field end` from the dependency chain described above.
- Without L20: 470 tokens; removes `local date, region, product = fields[1], fields[2], fields[3]` from the dependency chain described above.
- Without L21: 473 tokens; removes `local quantity, price = tonumber(fields[4]), tonumber(fields[5])` from the dependency chain described above.
- Without L22: 487 tokens; removes `local amount = quantity * price` from the dependency chain described above.
- Without L24: 477 tokens; removes `regions[region] = (regions[region] or 0) + amount` from the dependency chain described above.
- Without L25: 477 tokens; removes `products[product] = (products[product] or 0) + quantity` from the dependency chain described above.
- Without L27: 498 tokens; removes `end` from the dependency chain described above.
- Without L29: 491 tokens; removes `local function keys(values)` from the dependency chain described above.
- Without L30: 490 tokens; removes `local result = {}` from the dependency chain described above.
- Without L31: 470 tokens; removes `for key in pairs(values) do result[#result + 1] = key end` from the dependency chain described above.
- Without L32: 495 tokens; removes `return result` from the dependency chain described above.
- Without L33: 498 tokens; removes `end` from the dependency chain described above.
- Without L36: 487 tokens; removes `local region_names = keys(regions)` from the dependency chain described above.
- Without L37: 483 tokens; removes `table.sort(region_names, function(a, b)` from the dependency chain described above.
- Without L38: 467 tokens; removes `if regions[a] ~= regions[b] then return regions[a] > regions[b] end` from the dependency chain described above.
- Without L39: 491 tokens; removes `return a < b` from the dependency chain described above.
- Without L40: 497 tokens; removes `end)` from the dependency chain described above.
- Without L42: 487 tokens; removes `local product_names = keys(products)` from the dependency chain described above.
- Without L43: 491 tokens; removes `table.sort(product_names)` from the dependency chain described above.
