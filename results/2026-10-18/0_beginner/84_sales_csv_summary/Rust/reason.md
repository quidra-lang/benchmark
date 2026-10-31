# Task B selection: 84_sales_csv_summary / Rust

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.rs`. Selected original locations: L4,L6,L10,L11,L14,L16,L18,L19,L21,L22,L23,L24,L25,L27,L28,L30,L31,L32,L37.

- L4: `    let lines = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `        "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        "2026-04-02,north,marker,8,150",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        "2026-04-02,east,notebook,9,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        "2026-04-03,north,eraser,20,80",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        "2026-04-04,south,notebook,6,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    ];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `    let (mut regions, mut products, mut days) = (BTreeMap::new(), BTreeMap::new(), BTreeMap::new());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    for line in &lines[1..] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        let f: Vec<&str> = line.split(',').collect();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        let quantity: i32 = f[3].parse().unwrap();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        let price: i32 = f[4].parse().unwrap();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        let amount = quantity * price;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        *regions.entry(f[1]).or_insert(0) += amount;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        *products.entry(f[2]).or_insert(0) += quantity;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L31: `    let mut ranked: Vec<(&str, i32)> = regions.into_iter().collect();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    ranked.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    for (name, quantity) in products {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **442 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 426 tokens. The contiguous original span L4–L37 costs 744 tokens; the complete original source costs 877 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L4: 433 tokens; removes `let lines = [` from the dependency chain described above.
- Without L6: 415 tokens; removes `"2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L10: 416 tokens; removes `"2026-04-02,north,marker,8,150",` from the dependency chain described above.
- Without L11: 416 tokens; removes `"2026-04-02,east,notebook,9,200",` from the dependency chain described above.
- Without L14: 416 tokens; removes `"2026-04-03,north,eraser,20,80",` from the dependency chain described above.
- Without L16: 416 tokens; removes `"2026-04-04,south,notebook,6,200",` from the dependency chain described above.
- Without L18: 438 tokens; removes `];` from the dependency chain described above.
- Without L19: 392 tokens; removes `let (mut regions, mut products, mut days) = (BTreeMap::new(), BTreeMap::new(), BTreeMap::new());` from the dependency chain described above.
- Without L21: 426 tokens; removes `for line in &lines[1..] {` from the dependency chain described above.
- Without L22: 414 tokens; removes `let f: Vec<&str> = line.split(',').collect();` from the dependency chain described above.
- Without L23: 418 tokens; removes `let quantity: i32 = f[3].parse().unwrap();` from the dependency chain described above.
- Without L24: 418 tokens; removes `let price: i32 = f[4].parse().unwrap();` from the dependency chain described above.
- Without L25: 427 tokens; removes `let amount = quantity * price;` from the dependency chain described above.
- Without L27: 417 tokens; removes `*regions.entry(f[1]).or_insert(0) += amount;` from the dependency chain described above.
- Without L28: 417 tokens; removes `*products.entry(f[2]).or_insert(0) += quantity;` from the dependency chain described above.
- Without L30: 439 tokens; removes `}` from the dependency chain described above.
- Without L31: 408 tokens; removes `let mut ranked: Vec<(&str, i32)> = regions.into_iter().collect();` from the dependency chain described above.
- Without L32: 404 tokens; removes `ranked.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));` from the dependency chain described above.
- Without L37: 426 tokens; removes `for (name, quantity) in products {` from the dependency chain described above.
