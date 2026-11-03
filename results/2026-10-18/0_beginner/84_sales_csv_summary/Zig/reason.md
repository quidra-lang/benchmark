# Task B selection: 84_sales_csv_summary / Zig

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.zig`. Selected original locations: L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L16,L17,L18,L20,L21,L22,L28,L30,L34,L35,L38,L40,L42,L43,L44,L46,L47,L50,L51,L52,L53,L54,L55,L56,L57,L59,L60,L62,L63,L64.

- L5: `fn add(entries: *[12]Entry, len: *usize, name: []const u8, value: u32) void {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    for (entries[0..len.*]) |*e| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `        if (std.mem.eql(u8, e.name, name)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `            e.value += value;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `            return;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L11: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L12: `    entries[len.*] = .{ .name = name, .value = value };` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    len.* += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `fn nameLess(_: void, a: Entry, b: Entry) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    return std.mem.order(u8, a.name, b.name) == .lt;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `fn salesLess(_: void, a: Entry, b: Entry) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    return if (a.value != b.value) a.value > b.value else nameLess({}, a, b);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `    const lines = [_][]const u8{` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        "2026-04-02,north,marker,8,150",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        "2026-04-02,east,notebook,9,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        "2026-04-03,north,eraser,20,80",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `        "2026-04-04,south,notebook,6,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L43: `    var regions: [12]Entry = undefined;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `    var products: [12]Entry = undefined;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `    var rlen: usize = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `    var plen: usize = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `    for (lines[1..]) |line| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `        var fields = std.mem.splitScalar(u8, line, ',');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `        const date = fields.next().?;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `        const region = fields.next().?;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `        const product = fields.next().?;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `        const quantity = try std.fmt.parseInt(u32, fields.next().?, 10);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `        const price = try std.fmt.parseInt(u32, fields.next().?, 10);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `        const sales = quantity * price;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `        add(&regions, &rlen, region, sales);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `        add(&products, &plen, product, quantity);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L63: `    std.mem.sort(Entry, regions[0..rlen], {}, salesLess);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `    std.mem.sort(Entry, products[0..plen], {}, nameLess);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **756 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 720 tokens. The contiguous original span L5–L64 costs 1116 tokens; the complete original source costs 1387 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L5: 715 tokens; removes `fn add(entries: *[12]Entry, len: *usize, name: []const u8, value: u32) void {` from the dependency chain described above.
- Without L6: 736 tokens; removes `for (entries[0..len.*]) |*e| {` from the dependency chain described above.
- Without L7: 731 tokens; removes `if (std.mem.eql(u8, e.name, name)) {` from the dependency chain described above.
- Without L8: 744 tokens; removes `e.value += value;` from the dependency chain described above.
- Without L9: 750 tokens; removes `return;` from the dependency chain described above.
- Without L10: 752 tokens; removes `}` from the dependency chain described above.
- Without L11: 753 tokens; removes `}` from the dependency chain described above.
- Without L12: 726 tokens; removes `entries[len.*] = .{ .name = name, .value = value };` from the dependency chain described above.
- Without L13: 747 tokens; removes `len.* += 1;` from the dependency chain described above.
- Without L14: 754 tokens; removes `}` from the dependency chain described above.
- Without L16: 731 tokens; removes `fn nameLess(_: void, a: Entry, b: Entry) bool {` from the dependency chain described above.
- Without L17: 728 tokens; removes `return std.mem.order(u8, a.name, b.name) == .lt;` from the dependency chain described above.
- Without L18: 754 tokens; removes `}` from the dependency chain described above.
- Without L20: 731 tokens; removes `fn salesLess(_: void, a: Entry, b: Entry) bool {` from the dependency chain described above.
- Without L21: 713 tokens; removes `return if (a.value != b.value) a.value > b.value else nameLess({}, a, b);` from the dependency chain described above.
- Without L22: 754 tokens; removes `}` from the dependency chain described above.
- Without L28: 740 tokens; removes `const lines = [_][]const u8{` from the dependency chain described above.
- Without L30: 729 tokens; removes `"2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L34: 730 tokens; removes `"2026-04-02,north,marker,8,150",` from the dependency chain described above.
- Without L35: 730 tokens; removes `"2026-04-02,east,notebook,9,200",` from the dependency chain described above.
- Without L38: 730 tokens; removes `"2026-04-03,north,eraser,20,80",` from the dependency chain described above.
- Without L40: 730 tokens; removes `"2026-04-04,south,notebook,6,200",` from the dependency chain described above.
- Without L42: 752 tokens; removes `};` from the dependency chain described above.
- Without L43: 739 tokens; removes `var regions: [12]Entry = undefined;` from the dependency chain described above.
- Without L44: 739 tokens; removes `var products: [12]Entry = undefined;` from the dependency chain described above.
- Without L46: 743 tokens; removes `var rlen: usize = 0;` from the dependency chain described above.
- Without L47: 743 tokens; removes `var plen: usize = 0;` from the dependency chain described above.
- Without L50: 739 tokens; removes `for (lines[1..]) |line| {` from the dependency chain described above.
- Without L51: 729 tokens; removes `var fields = std.mem.splitScalar(u8, line, ',');` from the dependency chain described above.
- Without L52: 740 tokens; removes `const date = fields.next().?;` from the dependency chain described above.
- Without L53: 740 tokens; removes `const region = fields.next().?;` from the dependency chain described above.
- Without L54: 740 tokens; removes `const product = fields.next().?;` from the dependency chain described above.
- Without L55: 723 tokens; removes `const quantity = try std.fmt.parseInt(u32, fields.next().?, 10);` from the dependency chain described above.
- Without L56: 723 tokens; removes `const price = try std.fmt.parseInt(u32, fields.next().?, 10);` from the dependency chain described above.
- Without L57: 741 tokens; removes `const sales = quantity * price;` from the dependency chain described above.
- Without L59: 737 tokens; removes `add(&regions, &rlen, region, sales);` from the dependency chain described above.
- Without L60: 737 tokens; removes `add(&products, &plen, product, quantity);` from the dependency chain described above.
- Without L62: 753 tokens; removes `}` from the dependency chain described above.
- Without L63: 729 tokens; removes `std.mem.sort(Entry, regions[0..rlen], {}, salesLess);` from the dependency chain described above.
- Without L64: 729 tokens; removes `std.mem.sort(Entry, products[0..plen], {}, nameLess);` from the dependency chain described above.
