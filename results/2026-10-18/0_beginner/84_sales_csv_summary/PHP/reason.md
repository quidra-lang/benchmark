# Task B selection: 84_sales_csv_summary / PHP

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.php`. Selected original locations: L3,L5,L9,L10,L13,L15,L17,L18,L20,L21,L22,L23,L24,L26,L27,L29,L31,L32,L36,L37.

- L3: `$lines = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    '2026-04-01,north,notebook,10,200',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    '2026-04-02,north,marker,8,150',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    '2026-04-02,east,notebook,9,200',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    '2026-04-03,north,eraser,20,80',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    '2026-04-04,south,notebook,6,200',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `$regions = $products = $days = [];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `foreach (array_slice($lines, 1) as $line) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    [$date, $region, $product, $quantity, $price] = explode(',', $line);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    $quantity = (int) $quantity;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    $price = (int) $price;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    $amount = $quantity * $price;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    $regions[$region] = ($regions[$region] ?? 0) + $amount;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    $products[$product] = ($products[$product] ?? 0) + $quantity;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L31: `$regionNames = array_keys($regions);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `usort($regionNames, fn($a, $b) => ($regions[$b] <=> $regions[$a]) ?: strcmp($a, $b));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `ksort($products, SORT_STRING);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `foreach ($products as $product => $quantity) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **412 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 400 tokens. The contiguous original span L3–L37 costs 712 tokens; the complete original source costs 844 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 405 tokens; removes `$lines = [` from the dependency chain described above.
- Without L5: 386 tokens; removes `'2026-04-01,north,notebook,10,200',` from the dependency chain described above.
- Without L9: 387 tokens; removes `'2026-04-02,north,marker,8,150',` from the dependency chain described above.
- Without L10: 387 tokens; removes `'2026-04-02,east,notebook,9,200',` from the dependency chain described above.
- Without L13: 387 tokens; removes `'2026-04-03,north,eraser,20,80',` from the dependency chain described above.
- Without L15: 387 tokens; removes `'2026-04-04,south,notebook,6,200',` from the dependency chain described above.
- Without L17: 409 tokens; removes `];` from the dependency chain described above.
- Without L18: 394 tokens; removes `$regions = $products = $days = [];` from the dependency chain described above.
- Without L20: 390 tokens; removes `foreach (array_slice($lines, 1) as $line) {` from the dependency chain described above.
- Without L21: 376 tokens; removes `[$date, $region, $product, $quantity, $price] = explode(',', $line);` from the dependency chain described above.
- Without L22: 398 tokens; removes `$quantity = (int) $quantity;` from the dependency chain described above.
- Without L23: 398 tokens; removes `$price = (int) $price;` from the dependency chain described above.
- Without L24: 397 tokens; removes `$amount = $quantity * $price;` from the dependency chain described above.
- Without L26: 383 tokens; removes `$regions[$region] = ($regions[$region] ?? 0) + $amount;` from the dependency chain described above.
- Without L27: 383 tokens; removes `$products[$product] = ($products[$product] ?? 0) + $quantity;` from the dependency chain described above.
- Without L29: 410 tokens; removes `}` from the dependency chain described above.
- Without L31: 397 tokens; removes `$regionNames = array_keys($regions);` from the dependency chain described above.
- Without L32: 361 tokens; removes `usort($regionNames, fn($a, $b) => ($regions[$b] <=> $regions[$a]) ?: strcmp($a, $b));` from the dependency chain described above.
- Without L36: 400 tokens; removes `ksort($products, SORT_STRING);` from the dependency chain described above.
- Without L37: 393 tokens; removes `foreach ($products as $product => $quantity) {` from the dependency chain described above.
