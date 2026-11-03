# Task B selection: 73_merge_sort_inversions / Zig

## Common answer requirements

Identify merge-trace formatting and inversion state lifetime; explain appending one space plus inversions=K with cumulative increments from all completed earlier work, preserving final sorted/inversions lines.

## Supported analysis

Append " inversions=" and the ordinary decimal cumulative count at the merge trace after all merged values and before its newline. A shared counter threaded through recursion, captured by a closure, or carried as incoming/outgoing state already includes earlier merges: reuse that counter at the trace. Where the current count is only a subtree return value, it is insufficient during a right-subtree trace because it excludes completed work elsewhere. Add a separate shared cumulative counter initialized once at the top call, increment it by the same cross-inversion delta at each existing increment site, pass/capture it in recursive calls, and print it at the trace; retain the current subtree return values for unchanged final reporting. Do not add returned child counts into the shared counter a second time. An equivalent solution threads an incoming count offset left-first, then into the right call with the completed left count, and prints offset plus completed subtree count. The selected signatures/calls, increment, return and trace/output boundary establish the affected paths.

inversions:*usize is shared through both recursive calls and incremented through inversions.*. Append it before the current writeByte newline. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.zig`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 3 | 56 | `fn mergeSort(out: *std.Io.Writer, a: *[10]i32, l: usize, r: usize, inversions: *usize) std.Io.Writer.Error!void {` |
| 4 | 11 | `    if (l == r)` |
| 5 | 5 | `        return;` |
| 6 | 20 | `    const m = (l + r) / 2;` |
| 7 | 22 | `    try mergeSort(out, a, l, m, inversions);` |
| 8 | 26 | `    try mergeSort(out, a, m + 1, r, inversions);` |
| 18 | 19 | `            inversions.* += m - i + 1;` |
| 31 | 34 | `    try out.print("merge [{d}..{d}]:", .{ l, r });` |
| 32 | 16 | `    for (temp[0..len]) \|v\|` |
| 33 | 23 | `        try out.print(" {d}", .{v});` |
| 34 | 15 | `    try out.writeByte('\n');` |
| 35 | 2 | `}` |
| 42 | 13 | `    var inversions: usize = 0;` |
| 43 | 24 | `    try mergeSort(out, &a, 0, 9, &inversions);` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **286 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 844 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 295 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
