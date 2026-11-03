# Task B selection: 84_sales_csv_summary / C++

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.cpp`. Selected original locations: L10,L12,L13,L14,L15,L17,L18,L19,L20,L21,L22,L24,L25,L27,L28,L29,L30,L31,L35.

- L10: `    std::array<std::string, 13> lines = {"date,region,product,quantity,unit_price", "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        "2026-04-02,north,marker,8,150", "2026-04-02,east,notebook,9,200", "2026-04-03,south,stapler,3,600",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        "2026-04-03,west,eraser,15,80", "2026-04-03,north,eraser,20,80", "2026-04-04,east,stapler,5,600",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        "2026-04-04,south,notebook,6,200", "2026-04-04,west,marker,8,150"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    std::map<std::string, int> regions, products, days;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    for (int i = 1; i < 13; i++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        std::istringstream input(lines[i]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        std::array<std::string, 5> fields;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        for (std::string &field : fields)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `            std::getline(input, field, ',');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        int quantity = std::stoi(fields[3]), amount = quantity * std::stoi(fields[4]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        regions[fields[1]] += amount;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        products[fields[2]] += quantity;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `    std::vector<std::pair<std::string, int>> ranked(regions.begin(), regions.end());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    std::sort(ranked.begin(), ranked.end(), [](const auto &a, const auto &b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        return a.second != b.second ? a.second > b.second : a.first < b.first;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    for (const auto &[name, quantity] : products)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **582 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 574 tokens. The contiguous original span L10–L35 costs 764 tokens; the complete original source costs 963 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L10: 523 tokens; removes `std::array<std::string, 13> lines = {"date,region,product,quantity,unit_price", "2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L12: 508 tokens; removes `"2026-04-02,north,marker,8,150", "2026-04-02,east,notebook,9,200", "2026-04-03,south,stapler,3,600",` from the dependency chain described above.
- Without L13: 508 tokens; removes `"2026-04-03,west,eraser,15,80", "2026-04-03,north,eraser,20,80", "2026-04-04,east,stapler,5,600",` from the dependency chain described above.
- Without L14: 531 tokens; removes `"2026-04-04,south,notebook,6,200", "2026-04-04,west,marker,8,150"};` from the dependency chain described above.
- Without L15: 560 tokens; removes `std::map<std::string, int> regions, products, days;` from the dependency chain described above.
- Without L17: 555 tokens; removes `for (int i = 1; i < 13; i++) {` from the dependency chain described above.
- Without L18: 567 tokens; removes `std::istringstream input(lines[i]);` from the dependency chain described above.
- Without L19: 565 tokens; removes `std::array<std::string, 5> fields;` from the dependency chain described above.
- Without L20: 565 tokens; removes `for (std::string &field : fields)` from the dependency chain described above.
- Without L21: 563 tokens; removes `std::getline(input, field, ',');` from the dependency chain described above.
- Without L22: 544 tokens; removes `int quantity = std::stoi(fields[3]), amount = quantity * std::stoi(fields[4]);` from the dependency chain described above.
- Without L24: 568 tokens; removes `regions[fields[1]] += amount;` from the dependency chain described above.
- Without L25: 568 tokens; removes `products[fields[2]] += quantity;` from the dependency chain described above.
- Without L27: 579 tokens; removes `}` from the dependency chain described above.
- Without L28: 548 tokens; removes `std::vector<std::pair<std::string, int>> ranked(regions.begin(), regions.end());` from the dependency chain described above.
- Without L29: 543 tokens; removes `std::sort(ranked.begin(), ranked.end(), [](const auto &a, const auto &b) {` from the dependency chain described above.
- Without L30: 543 tokens; removes `return a.second != b.second ? a.second > b.second : a.first < b.first;` from the dependency chain described above.
- Without L31: 577 tokens; removes `});` from the dependency chain described above.
- Without L35: 561 tokens; removes `for (const auto &[name, quantity] : products)` from the dependency chain described above.
