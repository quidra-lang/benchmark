# Task B selection: 84_sales_csv_summary / Kotlin

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.kt`. Selected original locations: L2,L4,L8,L9,L12,L14,L15,L16,L17,L19,L20,L21,L22,L23,L24,L26,L28,L30.

- L2: `    val lines = listOf(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `        "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `        "2026-04-02,north,marker,8,150",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        "2026-04-02,east,notebook,9,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        "2026-04-03,north,eraser,20,80",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        "2026-04-04,south,notebook,6,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        "2026-04-04,west,marker,8,150")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    val regions = mutableMapOf<String, Int>()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    val products = sortedMapOf<String, Int>()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    for (line in lines.drop(1)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        val fields = line.split(',')` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        val quantity = fields[3].toInt()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        val amount = quantity * fields[4].toInt()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        regions[fields[1]] = regions.getOrDefault(fields[1], 0) + amount` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        products[fields[2]] = products.getOrDefault(fields[2], 0) + quantity` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `    val names = regions.keys.sortedWith(compareByDescending<String> { regions.getValue(it) }.thenBy { it })` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    for ((name, quantity) in products) println("$name: $quantity")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **412 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 372 tokens. The contiguous original span L2–L30 costs 685 tokens; the complete original source costs 764 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L2: 401 tokens; removes `val lines = listOf(` from the dependency chain described above.
- Without L4: 385 tokens; removes `"2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L8: 386 tokens; removes `"2026-04-02,north,marker,8,150",` from the dependency chain described above.
- Without L9: 386 tokens; removes `"2026-04-02,east,notebook,9,200",` from the dependency chain described above.
- Without L12: 386 tokens; removes `"2026-04-03,north,eraser,20,80",` from the dependency chain described above.
- Without L14: 386 tokens; removes `"2026-04-04,south,notebook,6,200",` from the dependency chain described above.
- Without L15: 386 tokens; removes `"2026-04-04,west,marker,8,150")` from the dependency chain described above.
- Without L16: 393 tokens; removes `val regions = mutableMapOf<String, Int>()` from the dependency chain described above.
- Without L17: 393 tokens; removes `val products = sortedMapOf<String, Int>()` from the dependency chain described above.
- Without L19: 394 tokens; removes `for (line in lines.drop(1)) {` from the dependency chain described above.
- Without L20: 395 tokens; removes `val fields = line.split(',')` from the dependency chain described above.
- Without L21: 395 tokens; removes `val quantity = fields[3].toInt()` from the dependency chain described above.
- Without L22: 391 tokens; removes `val amount = quantity * fields[4].toInt()` from the dependency chain described above.
- Without L23: 382 tokens; removes `regions[fields[1]] = regions.getOrDefault(fields[1], 0) + amount` from the dependency chain described above.
- Without L24: 382 tokens; removes `products[fields[2]] = products.getOrDefault(fields[2], 0) + quantity` from the dependency chain described above.
- Without L26: 409 tokens; removes `}` from the dependency chain described above.
- Without L28: 370 tokens; removes `val names = regions.keys.sortedWith(compareByDescending<String> { regions.getValue(it) }.thenBy { it })` from the dependency chain described above.
- Without L30: 384 tokens; removes `for ((name, quantity) in products) println("$name: $quantity")` from the dependency chain described above.
