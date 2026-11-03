# Task B selection: 90_kruskal_mst / Zig

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.zig`. Selected original locations: L3,L4,L5,L7,L8,L9,L10,L11,L12,L13,L14,L20,L21,L22,L23,L25,L27,L28,L29,L30,L32,L33,L34,L35,L36,L37,L38,L39,L40,L43,L44,L47,L48.

- L3: `fn less(_: void, a: [3]usize, b: [3]usize) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    return a[2] < b[2];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `fn find(parent: *[8]usize, initial: usize) usize {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    var v = initial;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    while (parent[v] != v) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        parent[v] = parent[parent[v]];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        v = parent[v];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `    return v;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `    var edges = [_][3]usize{` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        .{ 0, 1, 7 },  .{ 2, 0, 4 },  .{ 1, 2, 9 },  .{ 1, 3, 14 }, .{ 3, 2, 6 },  .{ 2, 4, 3 },` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        .{ 4, 3, 5 },  .{ 5, 3, 11 }, .{ 4, 6, 16 }, .{ 6, 5, 8 },  .{ 7, 5, 12 }, .{ 6, 7, 2 },` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        .{ 7, 4, 10 },` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    std.mem.sort([3]usize, &edges, {}, less);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    for (0..8) |i|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        parent[i] = i;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    var accepted: usize = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    var skipped: usize = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    for (edges) |e| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        const a = find(&parent, e[0]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        const b = find(&parent, e[1]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        if (a == b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `            skipped += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `            continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `        parent[a] = b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `        accepted += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `            'A' + @as(u8, @intCast(@min(e[0], e[1]))),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `            'A' + @as(u8, @intCast(@max(e[0], e[1]))),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `        if (accepted == 7)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `            break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **625 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 524 tokens. The contiguous original span L3–L48 costs 802 tokens; the complete original source costs 873 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 595 tokens; removes `fn less(_: void, a: [3]usize, b: [3]usize) bool {` from the dependency chain described above.
- Without L4: 609 tokens; removes `return a[2] < b[2];` from the dependency chain described above.
- Without L5: 623 tokens; removes `}` from the dependency chain described above.
- Without L7: 601 tokens; removes `fn find(parent: *[8]usize, initial: usize) usize {` from the dependency chain described above.
- Without L8: 615 tokens; removes `var v = initial;` from the dependency chain described above.
- Without L9: 609 tokens; removes `while (parent[v] != v) {` from the dependency chain described above.
- Without L10: 608 tokens; removes `parent[v] = parent[parent[v]];` from the dependency chain described above.
- Without L11: 613 tokens; removes `v = parent[v];` from the dependency chain described above.
- Without L12: 622 tokens; removes `}` from the dependency chain described above.
- Without L13: 619 tokens; removes `return v;` from the dependency chain described above.
- Without L14: 623 tokens; removes `}` from the dependency chain described above.
- Without L20: 609 tokens; removes `var edges = [_][3]usize{` from the dependency chain described above.
- Without L21: 538 tokens; removes `.{ 0, 1, 7 },  .{ 2, 0, 4 },  .{ 1, 2, 9 },  .{ 1, 3, 14 }, .{ 3, 2, 6 },  .{ 2, 4, 3 },` from the dependency chain described above.
- Without L22: 536 tokens; removes `.{ 4, 3, 5 },  .{ 5, 3, 11 }, .{ 4, 6, 16 }, .{ 6, 5, 8 },  .{ 7, 5, 12 }, .{ 6, 7, 2 },` from the dependency chain described above.
- Without L23: 608 tokens; removes `.{ 7, 4, 10 },` from the dependency chain described above.
- Without L25: 600 tokens; removes `std.mem.sort([3]usize, &edges, {}, less);` from the dependency chain described above.
- Without L27: 612 tokens; removes `for (0..8) |i|` from the dependency chain described above.
- Without L28: 613 tokens; removes `parent[i] = i;` from the dependency chain described above.
- Without L29: 612 tokens; removes `var accepted: usize = 0;` from the dependency chain described above.
- Without L30: 612 tokens; removes `var skipped: usize = 0;` from the dependency chain described above.
- Without L32: 612 tokens; removes `for (edges) |e| {` from the dependency chain described above.
- Without L33: 604 tokens; removes `const a = find(&parent, e[0]);` from the dependency chain described above.
- Without L34: 604 tokens; removes `const b = find(&parent, e[1]);` from the dependency chain described above.
- Without L35: 611 tokens; removes `if (a == b) {` from the dependency chain described above.
- Without L36: 615 tokens; removes `skipped += 1;` from the dependency chain described above.
- Without L37: 619 tokens; removes `continue;` from the dependency chain described above.
- Without L38: 621 tokens; removes `}` from the dependency chain described above.
- Without L39: 613 tokens; removes `parent[a] = b;` from the dependency chain described above.
- Without L40: 616 tokens; removes `accepted += 1;` from the dependency chain described above.
- Without L43: 588 tokens; removes `'A' + @as(u8, @intCast(@min(e[0], e[1]))),` from the dependency chain described above.
- Without L44: 588 tokens; removes `'A' + @as(u8, @intCast(@max(e[0], e[1]))),` from the dependency chain described above.
- Without L47: 613 tokens; removes `if (accepted == 7)` from the dependency chain described above.
- Without L48: 619 tokens; removes `break;` from the dependency chain described above.
