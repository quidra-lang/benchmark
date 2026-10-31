# Task B selection: 84_sales_csv_summary / Swift

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.swift`. Selected original locations: L1,L3,L7,L8,L11,L13,L14,L15,L16,L17,L18,L19,L20,L22,L24,L26.

- L1: `let lines = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    "2026-04-02,north,marker,8,150",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    "2026-04-02,east,notebook,9,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    "2026-04-03,north,eraser,20,80",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    "2026-04-04,south,notebook,6,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    "2026-04-04,west,marker,8,150"]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `var regions = [String: Int](), products = [String: Int](), days = [String: Int]()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `for line in lines.dropFirst() {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    let fields = line.split(separator: ",").map(String.init)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    let quantity = Int(fields[3])!, amount = quantity * Int(fields[4])!` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    regions[fields[1], default: 0] += amount` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    products[fields[2], default: 0] += quantity` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `let names = regions.keys.sorted { regions[$0]! == regions[$1]! ? $0 < $1 : regions[$0]! > regions[$1]! }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `for name in products.keys.sorted() { print("\(name): \(products[name]!)") }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **415 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 380 tokens. The contiguous original span L1–L26 costs 655 tokens; the complete original source costs 742 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 407 tokens; removes `let lines = [` from the dependency chain described above.
- Without L3: 389 tokens; removes `"2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L7: 390 tokens; removes `"2026-04-02,north,marker,8,150",` from the dependency chain described above.
- Without L8: 390 tokens; removes `"2026-04-02,east,notebook,9,200",` from the dependency chain described above.
- Without L11: 390 tokens; removes `"2026-04-03,north,eraser,20,80",` from the dependency chain described above.
- Without L13: 390 tokens; removes `"2026-04-04,south,notebook,6,200",` from the dependency chain described above.
- Without L14: 390 tokens; removes `"2026-04-04,west,marker,8,150"]` from the dependency chain described above.
- Without L15: 372 tokens; removes `var regions = [String: Int](), products = [String: Int](), days = [String: Int]()` from the dependency chain described above.
- Without L16: 400 tokens; removes `for line in lines.dropFirst() {` from the dependency chain described above.
- Without L17: 389 tokens; removes `let fields = line.split(separator: ",").map(String.init)` from the dependency chain described above.
- Without L18: 381 tokens; removes `let quantity = Int(fields[3])!, amount = quantity * Int(fields[4])!` from the dependency chain described above.
- Without L19: 396 tokens; removes `regions[fields[1], default: 0] += amount` from the dependency chain described above.
- Without L20: 396 tokens; removes `products[fields[2], default: 0] += quantity` from the dependency chain described above.
- Without L22: 413 tokens; removes `}` from the dependency chain described above.
- Without L24: 355 tokens; removes `let names = regions.keys.sorted { regions[$0]! == regions[$1]! ? $0 < $1 : regions[$0]! > regions[$1]! }` from the dependency chain described above.
- Without L26: 377 tokens; removes `for name in products.keys.sorted() { print("\(name): \(products[name]!)") }` from the dependency chain described above.
