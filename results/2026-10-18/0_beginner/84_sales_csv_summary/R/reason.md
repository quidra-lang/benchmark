# Task B selection: 84_sales_csv_summary / R

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.R`. Selected original locations: L1,L3,L7,L8,L11,L13,L15,L16,L17,L18,L19,L20,L23,L24.

- L1: `lines <- c(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  "2026-04-02,north,marker,8,150",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `  "2026-04-02,east,notebook,9,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  "2026-04-03,north,eraser,20,80",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `  "2026-04-04,south,notebook,6,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `)` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `fields <- do.call(rbind, strsplit(lines[-1], ",", fixed = TRUE))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `quantities <- as.integer(fields[, 4])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `amounts <- quantities * as.integer(fields[, 5])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `regions <- tapply(amounts, fields[, 2], sum)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `products <- tapply(quantities, fields[, 3], sum)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `for (i in order(-regions, names(regions), method = "radix")) cat(sprintf("%s: %d\n", names(regions)[i], regions[i]))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `for (product in sort(names(products), method = "radix")) cat(sprintf("%s: %d\n", product, products[product]))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **354 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 345 tokens. The contiguous original span L1–L24 costs 586 tokens; the complete original source costs 635 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 347 tokens; removes `lines <- c(` from the dependency chain described above.
- Without L3: 328 tokens; removes `"2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L7: 329 tokens; removes `"2026-04-02,north,marker,8,150",` from the dependency chain described above.
- Without L8: 329 tokens; removes `"2026-04-02,east,notebook,9,200",` from the dependency chain described above.
- Without L11: 329 tokens; removes `"2026-04-03,north,eraser,20,80",` from the dependency chain described above.
- Without L13: 329 tokens; removes `"2026-04-04,south,notebook,6,200",` from the dependency chain described above.
- Without L15: 352 tokens; removes `)` from the dependency chain described above.
- Without L16: 321 tokens; removes `fields <- do.call(rbind, strsplit(lines[-1], ",", fixed = TRUE))` from the dependency chain described above.
- Without L17: 338 tokens; removes `quantities <- as.integer(fields[, 4])` from the dependency chain described above.
- Without L18: 334 tokens; removes `amounts <- quantities * as.integer(fields[, 5])` from the dependency chain described above.
- Without L19: 334 tokens; removes `regions <- tapply(amounts, fields[, 2], sum)` from the dependency chain described above.
- Without L20: 334 tokens; removes `products <- tapply(quantities, fields[, 3], sum)` from the dependency chain described above.
- Without L23: 294 tokens; removes `for (i in order(-regions, names(regions), method = "radix")) cat(sprintf("%s: %d\n", names(regions)[i], regions[i]))` from the dependency chain described above.
- Without L24: 304 tokens; removes `for (product in sort(names(products), method = "radix")) cat(sprintf("%s: %d\n", product, products[product]))` from the dependency chain described above.
