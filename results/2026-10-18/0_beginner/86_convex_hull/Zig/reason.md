# Task B selection: 86_convex_hull / Zig

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.zig`. Selected original locations: L3,L4,L5,L7,L8,L9,L15,L16,L17,L18,L19,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L38,L39,L40.

- L3: `fn less(_: void, a: [2]i32, b: [2]i32) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    return if (a[0] != b[0]) a[0] < b[0] else a[1] < b[1];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `fn cross(o: [2]i32, a: [2]i32, b: [2]i32) i32 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `    var points = [_][2]i32{` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        .{ 3, 2 }, .{ -6, 1 },  .{ 8, 4 },  .{ 0, 0 },  .{ -3, 7 }, .{ 4, -3 }, .{ 1, -5 }, .{ -2, 1 },` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        .{ 5, 6 }, .{ -6, -2 }, .{ 2, -2 }, .{ 7, -1 }, .{ -3, 4 }, .{ 2, 8 },  .{ -6, 3 },` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `    std.mem.sort([2]i32, &points, {}, less);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    var llen: usize = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    var ulen: usize = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    for (points) |p| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        while (llen >= 2 and cross(lower[llen - 2], lower[llen - 1], p) <= 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `            llen -= 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        lower[llen] = p;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        llen += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `    var reverse = std.mem.reverseIterator(&points);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    while (reverse.next()) |p| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        while (ulen >= 2 and cross(upper[ulen - 2], upper[ulen - 1], p) <= 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `            ulen -= 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        upper[ulen] = p;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        ulen += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L38: `    const len = llen + ulen - 2;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    @memcpy(hull[0 .. llen - 1], lower[0 .. llen - 1]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    @memcpy(hull[llen - 1 .. len], upper[0 .. ulen - 1]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **716 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 702 tokens. The contiguous original span L3–L40 costs 865 tokens; the complete original source costs 1108 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 686 tokens; removes `fn less(_: void, a: [2]i32, b: [2]i32) bool {` from the dependency chain described above.
- Without L4: 670 tokens; removes `return if (a[0] != b[0]) a[0] < b[0] else a[1] < b[1];` from the dependency chain described above.
- Without L5: 714 tokens; removes `}` from the dependency chain described above.
- Without L7: 684 tokens; removes `fn cross(o: [2]i32, a: [2]i32, b: [2]i32) i32 {` from the dependency chain described above.
- Without L8: 650 tokens; removes `return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);` from the dependency chain described above.
- Without L9: 714 tokens; removes `}` from the dependency chain described above.
- Without L15: 700 tokens; removes `var points = [_][2]i32{` from the dependency chain described above.
- Without L16: 621 tokens; removes `.{ 3, 2 }, .{ -6, 1 },  .{ 8, 4 },  .{ 0, 0 },  .{ -3, 7 }, .{ 4, -3 }, .{ 1, -5 }, .{ -2, 1 },` from the dependency chain described above.
- Without L17: 631 tokens; removes `.{ 5, 6 }, .{ -6, -2 }, .{ 2, -2 }, .{ 7, -1 }, .{ -3, 4 }, .{ 2, 8 },  .{ -6, 3 },` from the dependency chain described above.
- Without L18: 712 tokens; removes `};` from the dependency chain described above.
- Without L19: 691 tokens; removes `std.mem.sort([2]i32, &points, {}, less);` from the dependency chain described above.
- Without L22: 703 tokens; removes `var llen: usize = 0;` from the dependency chain described above.
- Without L23: 703 tokens; removes `var ulen: usize = 0;` from the dependency chain described above.
- Without L24: 703 tokens; removes `for (points) |p| {` from the dependency chain described above.
- Without L25: 673 tokens; removes `while (llen >= 2 and cross(lower[llen - 2], lower[llen - 1], p) <= 0)` from the dependency chain described above.
- Without L26: 706 tokens; removes `llen -= 1;` from the dependency chain described above.
- Without L27: 704 tokens; removes `lower[llen] = p;` from the dependency chain described above.
- Without L28: 707 tokens; removes `llen += 1;` from the dependency chain described above.
- Without L29: 713 tokens; removes `}` from the dependency chain described above.
- Without L30: 697 tokens; removes `var reverse = std.mem.reverseIterator(&points);` from the dependency chain described above.
- Without L31: 699 tokens; removes `while (reverse.next()) |p| {` from the dependency chain described above.
- Without L32: 673 tokens; removes `while (ulen >= 2 and cross(upper[ulen - 2], upper[ulen - 1], p) <= 0)` from the dependency chain described above.
- Without L33: 706 tokens; removes `ulen -= 1;` from the dependency chain described above.
- Without L34: 704 tokens; removes `upper[ulen] = p;` from the dependency chain described above.
- Without L35: 707 tokens; removes `ulen += 1;` from the dependency chain described above.
- Without L36: 713 tokens; removes `}` from the dependency chain described above.
- Without L38: 698 tokens; removes `const len = llen + ulen - 2;` from the dependency chain described above.
- Without L39: 683 tokens; removes `@memcpy(hull[0 .. llen - 1], lower[0 .. llen - 1]);` from the dependency chain described above.
- Without L40: 683 tokens; removes `@memcpy(hull[llen - 1 .. len], upper[0 .. ulen - 1]);` from the dependency chain described above.
