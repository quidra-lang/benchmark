# Task B selection: 84_sales_csv_summary / Dart

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.dart`. Selected original locations: L2,L4,L8,L9,L12,L14,L16,L17,L18,L21,L22,L23,L24,L26,L27,L29,L30,L31,L32,L33,L34,L35.

- L2: `  const lines = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    '2026-04-01,north,notebook,10,200',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    '2026-04-02,north,marker,8,150',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    '2026-04-02,east,notebook,9,200',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    '2026-04-03,north,eraser,20,80',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    '2026-04-04,south,notebook,6,200',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `  ];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `  final regions = <String, int>{};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `  final products = <String, int>{};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `  for (final line in lines.skip(1)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    final f = line.split(',');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    final quantity = int.parse(f[3]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    final sales = quantity * int.parse(f[4]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    regions[f[1]] = (regions[f[1]] ?? 0) + sales;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    products[f[2]] = (products[f[2]] ?? 0) + quantity;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `  final regionNames = regions.keys.toList()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    ..sort((a, b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `      final c = regions[b]!.compareTo(regions[a]!);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `      return c != 0 ? c : a.compareTo(b);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `  final productNames = products.keys.toList()..sort();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **415 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 394 tokens. The contiguous original span L2–L35 costs 669 tokens; the complete original source costs 860 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L2: 406 tokens; removes `const lines = [` from the dependency chain described above.
- Without L4: 389 tokens; removes `'2026-04-01,north,notebook,10,200',` from the dependency chain described above.
- Without L8: 390 tokens; removes `'2026-04-02,north,marker,8,150',` from the dependency chain described above.
- Without L9: 390 tokens; removes `'2026-04-02,east,notebook,9,200',` from the dependency chain described above.
- Without L12: 390 tokens; removes `'2026-04-03,north,eraser,20,80',` from the dependency chain described above.
- Without L14: 390 tokens; removes `'2026-04-04,south,notebook,6,200',` from the dependency chain described above.
- Without L16: 411 tokens; removes `];` from the dependency chain described above.
- Without L17: 398 tokens; removes `final regions = <String, int>{};` from the dependency chain described above.
- Without L18: 398 tokens; removes `final products = <String, int>{};` from the dependency chain described above.
- Without L21: 395 tokens; removes `for (final line in lines.skip(1)) {` from the dependency chain described above.
- Without L22: 398 tokens; removes `final f = line.split(',');` from the dependency chain described above.
- Without L23: 397 tokens; removes `final quantity = int.parse(f[3]);` from the dependency chain described above.
- Without L24: 393 tokens; removes `final sales = quantity * int.parse(f[4]);` from the dependency chain described above.
- Without L26: 387 tokens; removes `regions[f[1]] = (regions[f[1]] ?? 0) + sales;` from the dependency chain described above.
- Without L27: 387 tokens; removes `products[f[2]] = (products[f[2]] ?? 0) + quantity;` from the dependency chain described above.
- Without L29: 412 tokens; removes `}` from the dependency chain described above.
- Without L30: 398 tokens; removes `final regionNames = regions.keys.toList()` from the dependency chain described above.
- Without L31: 402 tokens; removes `..sort((a, b) {` from the dependency chain described above.
- Without L32: 391 tokens; removes `final c = regions[b]!.compareTo(regions[a]!);` from the dependency chain described above.
- Without L33: 390 tokens; removes `return c != 0 ? c : a.compareTo(b);` from the dependency chain described above.
- Without L34: 410 tokens; removes `});` from the dependency chain described above.
- Without L35: 393 tokens; removes `final productNames = products.keys.toList()..sort();` from the dependency chain described above.
