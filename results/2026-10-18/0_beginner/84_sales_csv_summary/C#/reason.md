# Task B selection: 84_sales_csv_summary / C#

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `Program.cs`. Selected original locations: L8,L10,L14,L15,L18,L20,L21,L22,L23,L25,L26,L27,L28,L29,L30,L31,L33,L35,L36,L38,L39.

- L8: `string[] lines = {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    "2026-04-02,north,marker,8,150",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    "2026-04-02,east,notebook,9,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    "2026-04-03,north,eraser,20,80",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    "2026-04-04,south,notebook,6,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    "2026-04-04,west,marker,8,150" };` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `var regions = new Dictionary<string, int>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `var products = new SortedDictionary<string, int>(StringComparer.Ordinal);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `foreach (string line in lines.Skip(1))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `    string[] fields = line.Split(',');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    int quantity = int.Parse(fields[3], CultureInfo.InvariantCulture);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    int amount = quantity * int.Parse(fields[4], CultureInfo.InvariantCulture);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    regions[fields[1]] = regions.GetValueOrDefault(fields[1]) + amount;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    products[fields[2]] = products.GetValueOrDefault(fields[2]) + quantity;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `foreach (var pair in regions.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L38: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `foreach (var pair in products) Console.WriteLine($"{pair.Key}: {pair.Value}");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **435 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 391 tokens. The contiguous original span L8–L39 costs 699 tokens; the complete original source costs 817 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L8: 426 tokens; removes `string[] lines = {` from the dependency chain described above.
- Without L10: 409 tokens; removes `"2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L14: 410 tokens; removes `"2026-04-02,north,marker,8,150",` from the dependency chain described above.
- Without L15: 410 tokens; removes `"2026-04-02,east,notebook,9,200",` from the dependency chain described above.
- Without L18: 410 tokens; removes `"2026-04-03,north,eraser,20,80",` from the dependency chain described above.
- Without L20: 410 tokens; removes `"2026-04-04,south,notebook,6,200",` from the dependency chain described above.
- Without L21: 408 tokens; removes `"2026-04-04,west,marker,8,150" };` from the dependency chain described above.
- Without L22: 416 tokens; removes `var regions = new Dictionary<string, int>();` from the dependency chain described above.
- Without L23: 411 tokens; removes `var products = new SortedDictionary<string, int>(StringComparer.Ordinal);` from the dependency chain described above.
- Without L25: 418 tokens; removes `foreach (string line in lines.Skip(1))` from the dependency chain described above.
- Without L26: 433 tokens; removes `{` from the dependency chain described above.
- Without L27: 417 tokens; removes `string[] fields = line.Split(',');` from the dependency chain described above.
- Without L28: 410 tokens; removes `int quantity = int.Parse(fields[3], CultureInfo.InvariantCulture);` from the dependency chain described above.
- Without L29: 406 tokens; removes `int amount = quantity * int.Parse(fields[4], CultureInfo.InvariantCulture);` from the dependency chain described above.
- Without L30: 407 tokens; removes `regions[fields[1]] = regions.GetValueOrDefault(fields[1]) + amount;` from the dependency chain described above.
- Without L31: 407 tokens; removes `products[fields[2]] = products.GetValueOrDefault(fields[2]) + quantity;` from the dependency chain described above.
- Without L33: 433 tokens; removes `}` from the dependency chain described above.
- Without L35: 392 tokens; removes `foreach (var pair in regions.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal))` from the dependency chain described above.
- Without L36: 433 tokens; removes `{` from the dependency chain described above.
- Without L38: 433 tokens; removes `}` from the dependency chain described above.
- Without L39: 401 tokens; removes `foreach (var pair in products) Console.WriteLine($"{pair.Key}: {pair.Value}");` from the dependency chain described above.
