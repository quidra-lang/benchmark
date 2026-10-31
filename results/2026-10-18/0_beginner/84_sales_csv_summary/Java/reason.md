# Task B selection: 84_sales_csv_summary / Java

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `Main.java`. Selected original locations: L10,L12,L16,L17,L20,L22,L23,L24,L25,L26,L27,L28,L29,L31,L33,L34,L35,L39.

- L10: `        String[] lines = {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `            "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `            "2026-04-02,north,marker,8,150",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `            "2026-04-02,east,notebook,9,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `            "2026-04-03,north,eraser,20,80",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `            "2026-04-04,south,notebook,6,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `            "2026-04-04,west,marker,8,150"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        Map<String, Integer> regions = new HashMap<>(), products = new TreeMap<>(), days = new TreeMap<>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        for (int i = 1; i < lines.length; i++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `            String[] fields = lines[i].split(",");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `            int quantity = Integer.parseInt(fields[3]), amount = quantity * Integer.parseInt(fields[4]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            regions.merge(fields[1], amount, Integer::sum);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `            products.merge(fields[2], quantity, Integer::sum);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `        List<String> names = new ArrayList<>(regions.keySet());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        names.sort(Comparator.<String>comparingInt(regions::get).reversed()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `                .thenComparing(Comparator.naturalOrder()));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `        for (var entry : products.entrySet()) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **455 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 412 tokens. The contiguous original span L10–L39 costs 748 tokens; the complete original source costs 1006 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L10: 444 tokens; removes `String[] lines = {` from the dependency chain described above.
- Without L12: 427 tokens; removes `"2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L16: 428 tokens; removes `"2026-04-02,north,marker,8,150",` from the dependency chain described above.
- Without L17: 428 tokens; removes `"2026-04-02,east,notebook,9,200",` from the dependency chain described above.
- Without L20: 428 tokens; removes `"2026-04-03,north,eraser,20,80",` from the dependency chain described above.
- Without L22: 428 tokens; removes `"2026-04-04,south,notebook,6,200",` from the dependency chain described above.
- Without L23: 427 tokens; removes `"2026-04-04,west,marker,8,150"};` from the dependency chain described above.
- Without L24: 403 tokens; removes `Map<String, Integer> regions = new HashMap<>(), products = new TreeMap<>(), days = new TreeMap<>();` from the dependency chain described above.
- Without L25: 426 tokens; removes `for (int i = 1; i < lines.length; i++) {` from the dependency chain described above.
- Without L26: 433 tokens; removes `String[] fields = lines[i].split(",");` from the dependency chain described above.
- Without L27: 414 tokens; removes `int quantity = Integer.parseInt(fields[3]), amount = quantity * Integer.parseInt(fields[4]);` from the dependency chain described above.
- Without L28: 433 tokens; removes `regions.merge(fields[1], amount, Integer::sum);` from the dependency chain described above.
- Without L29: 433 tokens; removes `products.merge(fields[2], quantity, Integer::sum);` from the dependency chain described above.
- Without L31: 451 tokens; removes `}` from the dependency chain described above.
- Without L33: 428 tokens; removes `List<String> names = new ArrayList<>(regions.keySet());` from the dependency chain described above.
- Without L34: 433 tokens; removes `names.sort(Comparator.<String>comparingInt(regions::get).reversed()` from the dependency chain described above.
- Without L35: 437 tokens; removes `.thenComparing(Comparator.naturalOrder()));` from the dependency chain described above.
- Without L39: 434 tokens; removes `for (var entry : products.entrySet()) {` from the dependency chain described above.
