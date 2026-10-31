# Task B selection: 84_sales_csv_summary / Quidra

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.qui`. Selected original locations: L3,L4,L5,L7,L9,L13,L14,L17,L19,L21,L23,L24,L25,L26,L27,L28,L30,L31,L32,L33,L34,L36,L37,L38,L39,L40,L41,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57.

- L3: `int grouped_total(string key, string[] labels, int[] amounts)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    int[] selected = [for nat i < len(labels) if labels[i] == key then amounts[i]]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    return selected.sum()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `string[] csv = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    "2026-04-02,north,marker,8,150",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    "2026-04-02,east,notebook,9,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    "2026-04-03,north,eraser,20,80",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    "2026-04-04,south,notebook,6,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `string[] regions = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `string[] products = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `int[] quantities = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `int[] amounts = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `set.Set<string> region_set = set.Set<string>()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `set.Set<string> product_set = set.Set<string>()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `for 1 <= int i < int(len(csv))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    string[] fields = csv[i].split(",")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    int quantity = int.parse(fields[3])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    int price = int.parse(fields[4])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    int amount = quantity * price` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    regions = regions.append(fields[1])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    products = products.append(fields[2])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    quantities = quantities.append(quantity)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    amounts = amounts.append(amount)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    .region_set.add(fields[1])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    .product_set.add(fields[2])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `string[] region_names = region_set.values().sorted()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `int[] region_totals = [for string name = region_names[] then grouped_total(name, regions, amounts)]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `bool[] used = array(len(region_names), fill = false)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `for nat rank < len(region_names)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    int best = -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `    for nat i < len(region_names)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `        if not used[i]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `            if best == -1 or region_totals[i] > region_totals[best]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `                best = int(i)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `    used[best] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `    print("{region_names[best]}: {region_totals[best]}{NL}")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `string[] product_names = product_set.values().sorted()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `for string name = product_names[]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `    int quantity = grouped_total(name, products, quantities)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **727 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 716 tokens. The contiguous original span L3–L57 costs 998 tokens; the complete original source costs 1160 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 704 tokens; removes `int grouped_total(string key, string[] labels, int[] amounts)` from the dependency chain described above.
- Without L4: 687 tokens; removes `int[] selected = [for nat i < len(labels) if labels[i] == key then amounts[i]]` from the dependency chain described above.
- Without L5: 718 tokens; removes `return selected.sum()` from the dependency chain described above.
- Without L7: 718 tokens; removes `string[] csv = [` from the dependency chain described above.
- Without L9: 701 tokens; removes `"2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L13: 702 tokens; removes `"2026-04-02,north,marker,8,150",` from the dependency chain described above.
- Without L14: 702 tokens; removes `"2026-04-02,east,notebook,9,200",` from the dependency chain described above.
- Without L17: 702 tokens; removes `"2026-04-03,north,eraser,20,80",` from the dependency chain described above.
- Without L19: 702 tokens; removes `"2026-04-04,south,notebook,6,200",` from the dependency chain described above.
- Without L21: 725 tokens; removes `]` from the dependency chain described above.
- Without L23: 718 tokens; removes `string[] regions = []` from the dependency chain described above.
- Without L24: 718 tokens; removes `string[] products = []` from the dependency chain described above.
- Without L25: 718 tokens; removes `int[] quantities = []` from the dependency chain described above.
- Without L26: 718 tokens; removes `int[] amounts = []` from the dependency chain described above.
- Without L27: 705 tokens; removes `set.Set<string> region_set = set.Set<string>()` from the dependency chain described above.
- Without L28: 705 tokens; removes `set.Set<string> product_set = set.Set<string>()` from the dependency chain described above.
- Without L30: 707 tokens; removes `for 1 <= int i < int(len(csv))` from the dependency chain described above.
- Without L31: 708 tokens; removes `string[] fields = csv[i].split(",")` from the dependency chain described above.
- Without L32: 710 tokens; removes `int quantity = int.parse(fields[3])` from the dependency chain described above.
- Without L33: 710 tokens; removes `int price = int.parse(fields[4])` from the dependency chain described above.
- Without L34: 714 tokens; removes `int amount = quantity * price` from the dependency chain described above.
- Without L36: 712 tokens; removes `regions = regions.append(fields[1])` from the dependency chain described above.
- Without L37: 712 tokens; removes `products = products.append(fields[2])` from the dependency chain described above.
- Without L38: 715 tokens; removes `quantities = quantities.append(quantity)` from the dependency chain described above.
- Without L39: 715 tokens; removes `amounts = amounts.append(amount)` from the dependency chain described above.
- Without L40: 713 tokens; removes `.region_set.add(fields[1])` from the dependency chain described above.
- Without L41: 713 tokens; removes `.product_set.add(fields[2])` from the dependency chain described above.
- Without L44: 706 tokens; removes `string[] region_names = region_set.values().sorted()` from the dependency chain described above.
- Without L45: 688 tokens; removes `int[] region_totals = [for string name = region_names[] then grouped_total(name, regions, amounts)]` from the dependency chain described above.
- Without L46: 703 tokens; removes `bool[] used = array(len(region_names), fill = false)` from the dependency chain described above.
- Without L47: 712 tokens; removes `for nat rank < len(region_names)` from the dependency chain described above.
- Without L48: 717 tokens; removes `int best = -1` from the dependency chain described above.
- Without L49: 711 tokens; removes `for nat i < len(region_names)` from the dependency chain described above.
- Without L50: 716 tokens; removes `if not used[i]` from the dependency chain described above.
- Without L51: 697 tokens; removes `if best == -1 or region_totals[i] > region_totals[best]` from the dependency chain described above.
- Without L52: 714 tokens; removes `best = int(i)` from the dependency chain described above.
- Without L53: 717 tokens; removes `used[best] = true` from the dependency chain described above.
- Without L54: 700 tokens; removes `print("{region_names[best]}: {region_totals[best]}{NL}")` from the dependency chain described above.
- Without L55: 706 tokens; removes `string[] product_names = product_set.values().sorted()` from the dependency chain described above.
- Without L56: 714 tokens; removes `for string name = product_names[]` from the dependency chain described above.
- Without L57: 707 tokens; removes `int quantity = grouped_total(name, products, quantities)` from the dependency chain described above.
