# Task B selection: 84_sales_csv_summary / TypeScript

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.ts`. Selected original locations: L1,L3,L5,L7,L8,L9,L10,L12,L13,L14,L16,L17,L19,L20,L21,L24.

- L1: `const rows = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  "2026-04-01,north,notebook,10,200", "2026-04-01,east,marker,6,150",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  "2026-04-02,north,marker,8,150", "2026-04-02,east,notebook,9,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  "2026-04-03,north,eraser,20,80", "2026-04-04,east,stapler,5,600",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `  "2026-04-04,south,notebook,6,200", "2026-04-04,west,marker,8,150"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L10: `const regions = new Map<string, number>(), products = new Map<string, number>(), dates = new Map<string, number>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `for (const line of rows.slice(1)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `  const [date, region, product, quantityText, priceText] = line.split(",");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `  const quantity = Number(quantityText), sales = quantity * Number(priceText);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `  regions.set(region, (regions.get(region) ?? 0) + sales);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `  products.set(product, (products.get(product) ?? 0) + quantity);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `const alphabetical = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `const regionOrder = [...regions.keys()].sort((a, b) => regions.get(b)! - regions.get(a)! || alphabetical(a, b));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `for (const product of [...products.keys()].sort()) console.log(`${product}: ${products.get(product)}`);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **548 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 535 tokens. The contiguous original span L1–L24 costs 758 tokens; the complete original source costs 846 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 540 tokens; removes `const rows = [` from the dependency chain described above.
- Without L3: 498 tokens; removes `"2026-04-01,north,notebook,10,200", "2026-04-01,east,marker,6,150",` from the dependency chain described above.
- Without L5: 499 tokens; removes `"2026-04-02,north,marker,8,150", "2026-04-02,east,notebook,9,200",` from the dependency chain described above.
- Without L7: 499 tokens; removes `"2026-04-03,north,eraser,20,80", "2026-04-04,east,stapler,5,600",` from the dependency chain described above.
- Without L8: 500 tokens; removes `"2026-04-04,south,notebook,6,200", "2026-04-04,west,marker,8,150"` from the dependency chain described above.
- Without L9: 545 tokens; removes `];` from the dependency chain described above.
- Without L10: 495 tokens; removes `const regions = new Map<string, number>(), products = new Map<string, number>(), dates = new Map<string, number>();` from the dependency chain described above.
- Without L12: 529 tokens; removes `for (const line of rows.slice(1)) {` from the dependency chain described above.
- Without L13: 515 tokens; removes `const [date, region, product, quantityText, priceText] = line.split(",");` from the dependency chain described above.
- Without L14: 519 tokens; removes `const quantity = Number(quantityText), sales = quantity * Number(priceText);` from the dependency chain described above.
- Without L16: 521 tokens; removes `regions.set(region, (regions.get(region) ?? 0) + sales);` from the dependency chain described above.
- Without L17: 521 tokens; removes `products.set(product, (products.get(product) ?? 0) + quantity);` from the dependency chain described above.
- Without L19: 546 tokens; removes `}` from the dependency chain described above.
- Without L20: 498 tokens; removes `const alphabetical = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;` from the dependency chain described above.
- Without L21: 492 tokens; removes `const regionOrder = [...regions.keys()].sort((a, b) => regions.get(b)! - regions.get(a)! || alphabetical(a, b));` from the dependency chain described above.
- Without L24: 503 tokens; removes `for (const product of [...products.keys()].sort()) console.log(`${product}: ${products.get(product)}`);` from the dependency chain described above.
