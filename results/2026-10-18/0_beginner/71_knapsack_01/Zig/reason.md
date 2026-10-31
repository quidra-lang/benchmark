# Task B selection: 71_knapsack_01 / Zig

## Common answer requirements

Locate capacity/table bounds and reconstruction/output dependencies; explain capacity 15 plus maximum-value, minimum-total-weight, lexicographically smallest increasing original-position sequence tie resolution with proper prefix first, reconstructing from DP and keeping printed names in original order.

## Supported analysis

Replace capacity 20 with 15 at the capacity initialization, loops, final-table lookup and any literal weight calculation; a compact table now has capacities 0..15 (16 columns). The present numeric maximum and inequality-only backtracking do not encode all requested ties. Use DP records containing value, total weight, increasing original item-position sequence, and the corresponding take/skip reconstruction choice; compare records by larger value, then smaller weight, then ordinary lexicographic sequence order with shorter proper prefix first. A robust implementation can formulate suffix states built from later items backward: taking the current item prepends its original position to the child sequence, and skipping keeps the next suffix record. Store the chosen transition and reconstruct by following it from the capacity-15 root. This avoids assuming that a local take/skip preference establishes global lexicographic order. Print the selected maximum and actual selected weight, then names selected by increasing original positions using the current filter/forward scan (or current final reverse of backward reconstruction). No source modification is produced.

 The selected writer construction and out alias identify std.Io.Writer as the implementation of the visible print/write operations; buffer allocation/flush behavior is unrelated to this question. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.zig`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 5 | 32 | `    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);` |
| 6 | 13 | `    const out = &writer.interface;` |
| 8 | 37 | `    const weights = [_]usize{ 10, 3, 2, 3, 5, 5, 6 };` |
| 9 | 45 | `    const values = [_]u32{ 120, 65, 45, 20, 90, 85, 100 };` |
| 10 | 28 | `    var dp: [8][21]u32 = @splat(@splat(0));` |
| 11 | 15 | `    for (1..8) \|i\| {` |
| 12 | 17 | `        for (0..21) \|capacity\| {` |
| 13 | 26 | `            dp[i][capacity] = dp[i - 1][capacity];` |
| 14 | 20 | `            if (weights[i - 1] <= capacity)` |
| 15 | 61 | `                dp[i][capacity] = @max(dp[i][capacity], dp[i - 1][capacity - weights[i - 1]] + values[i - 1]);` |
| 16 | 4 | `        }` |
| 17 | 3 | `    }` |
| 18 | 20 | `    var chosen: [7]bool = @splat(false);` |
| 19 | 14 | `    var capacity: usize = 20;` |
| 20 | 12 | `    var i: usize = 7;` |
| 21 | 23 | `    while (i > 0) : (i -= 1) {` |
| 22 | 30 | `        if (dp[i][capacity] != dp[i - 1][capacity]) {` |
| 23 | 17 | `            chosen[i - 1] = true;` |
| 24 | 17 | `            capacity -= weights[i - 1];` |
| 25 | 4 | `        }` |
| 26 | 3 | `    }` |
| 27 | 55 | `    try out.print("max value: {d}\ntotal weight: {d}\nitems:", .{ dp[7][20], 20 - capacity });` |
| 28 | 19 | `    for (names, chosen) \|name, yes\| {` |
| 29 | 8 | `        if (yes)` |
| 30 | 24 | `            try out.print(" {s}", .{name});` |
| 31 | 3 | `    }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **550 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 688 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 552 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
