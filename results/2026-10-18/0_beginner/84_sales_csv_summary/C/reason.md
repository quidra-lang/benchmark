# Task B selection: 84_sales_csv_summary / C

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.c`. Selected original locations: L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L22,L23,L24,L25,L27,L28,L29,L32,L34,L35,L36,L37,L38,L39,L41,L44,L45,L46,L48,L49,L51,L52,L53.

- L10: `void add(Entry *entries, int *count, const char *name, int amount) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    int i = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    while (i < *count && strcmp(entries[i].name, name))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        i++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    if (i == *count) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        strcpy(entries[i].name, name);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        entries[i].total = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        (*count)++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `    entries[i].total += amount;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `int by_total(const void *a, const void *b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    const Entry *x = a, *y = b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    return x->total != y->total ? y->total - x->total : strcmp(x->name, y->name);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `int by_name(const void *a, const void *b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    return strcmp(((const Entry *)a)->name, ((const Entry *)b)->name);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `    const char *lines[] = {"date,region,product,quantity,unit_price", "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        "2026-04-02,north,marker,8,150", "2026-04-02,east,notebook,9,200", "2026-04-03,south,stapler,3,600",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        "2026-04-03,west,eraser,15,80", "2026-04-03,north,eraser,20,80", "2026-04-04,east,stapler,5,600",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        "2026-04-04,south,notebook,6,200", "2026-04-04,west,marker,8,150"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    Entry regions[12], products[12], days[12];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    int nr = 0, np = 0, nd = 0, total = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    for (int i = 1; i < 13; i++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `        strcpy(line, lines[i]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `        for (char *part = strtok(line, ","); part; part = strtok(NULL, ","))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `            fields[f++] = part;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `        int quantity = atoi(fields[3]), price = atoi(fields[4]), amount = quantity * price;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `        add(regions, &nr, fields[1], amount);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        add(products, &np, fields[2], quantity);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L52: `    qsort(regions, nr, sizeof(Entry), by_total);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `    qsort(products, np, sizeof(Entry), by_name);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **818 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 792 tokens. The contiguous original span L10–L53 costs 968 tokens; the complete original source costs 1215 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L10: 787 tokens; removes `void add(Entry *entries, int *count, const char *name, int amount) {` from the dependency chain described above.
- Without L11: 808 tokens; removes `int i = 0;` from the dependency chain described above.
- Without L12: 792 tokens; removes `while (i < *count && strcmp(entries[i].name, name))` from the dependency chain described above.
- Without L13: 812 tokens; removes `i++;` from the dependency chain described above.
- Without L14: 804 tokens; removes `if (i == *count) {` from the dependency chain described above.
- Without L15: 803 tokens; removes `strcpy(entries[i].name, name);` from the dependency chain described above.
- Without L16: 805 tokens; removes `entries[i].total = 0;` from the dependency chain described above.
- Without L17: 809 tokens; removes `(*count)++;` from the dependency chain described above.
- Without L18: 815 tokens; removes `}` from the dependency chain described above.
- Without L19: 806 tokens; removes `entries[i].total += amount;` from the dependency chain described above.
- Without L20: 816 tokens; removes `}` from the dependency chain described above.
- Without L22: 794 tokens; removes `int by_total(const void *a, const void *b) {` from the dependency chain described above.
- Without L23: 797 tokens; removes `const Entry *x = a, *y = b;` from the dependency chain described above.
- Without L24: 778 tokens; removes `return x->total != y->total ? y->total - x->total : strcmp(x->name, y->name);` from the dependency chain described above.
- Without L25: 816 tokens; removes `}` from the dependency chain described above.
- Without L27: 794 tokens; removes `int by_name(const void *a, const void *b) {` from the dependency chain described above.
- Without L28: 784 tokens; removes `return strcmp(((const Entry *)a)->name, ((const Entry *)b)->name);` from the dependency chain described above.
- Without L29: 816 tokens; removes `}` from the dependency chain described above.
- Without L32: 766 tokens; removes `const char *lines[] = {"date,region,product,quantity,unit_price", "2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L34: 744 tokens; removes `"2026-04-02,north,marker,8,150", "2026-04-02,east,notebook,9,200", "2026-04-03,south,stapler,3,600",` from the dependency chain described above.
- Without L35: 744 tokens; removes `"2026-04-03,west,eraser,15,80", "2026-04-03,north,eraser,20,80", "2026-04-04,east,stapler,5,600",` from the dependency chain described above.
- Without L36: 767 tokens; removes `"2026-04-04,south,notebook,6,200", "2026-04-04,west,marker,8,150"};` from the dependency chain described above.
- Without L37: 794 tokens; removes `Entry regions[12], products[12], days[12];` from the dependency chain described above.
- Without L38: 787 tokens; removes `int nr = 0, np = 0, nd = 0, total = 0;` from the dependency chain described above.
- Without L39: 791 tokens; removes `for (int i = 1; i < 13; i++) {` from the dependency chain described above.
- Without L41: 804 tokens; removes `strcpy(line, lines[i]);` from the dependency chain described above.
- Without L44: 777 tokens; removes `for (char *part = strtok(line, ","); part; part = strtok(NULL, ","))` from the dependency chain described above.
- Without L45: 804 tokens; removes `fields[f++] = part;` from the dependency chain described above.
- Without L46: 777 tokens; removes `int quantity = atoi(fields[3]), price = atoi(fields[4]), amount = quantity * price;` from the dependency chain described above.
- Without L48: 797 tokens; removes `add(regions, &nr, fields[1], amount);` from the dependency chain described above.
- Without L49: 797 tokens; removes `add(products, &np, fields[2], quantity);` from the dependency chain described above.
- Without L51: 815 tokens; removes `}` from the dependency chain described above.
- Without L52: 797 tokens; removes `qsort(regions, nr, sizeof(Entry), by_total);` from the dependency chain described above.
- Without L53: 797 tokens; removes `qsort(products, np, sizeof(Entry), by_name);` from the dependency chain described above.
