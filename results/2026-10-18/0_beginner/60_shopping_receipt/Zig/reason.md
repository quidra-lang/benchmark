# Task B selection: 60_shopping_receipt / Zig

## Common answer requirements

Trace actual food items into the category subtotal and its integer tax; explain where truncation occurs and why it is per category; follow that food tax to final payment and distinguish earlier untaxed item printing.

## Supported analysis

Food items are milk 198*2=396, bread 248*1=248, apple 128*4=512, and eggs 268*1=268. The food category reaches 1424 before tax; 1424*8/100=113.92 is truncated to 113 by the shown integer division/floor operation. Item lines print price times quantity before category tax calculation, so they are untaxed subtotals. Flooring the individual food taxes would instead give 31+19+40+21=111; the source does not do that. The selected final-payment expression adds the category subtotals and category taxes, so the food tax contributes exactly once. General subtotal/tax processing is shown only where it shares the final payment dependency or a complete source line.

u32 arithmetic makes / an integer quotient; the totals category branch maps true food to index zero. The selected writer construction and out alias identify std.Io.Writer as the implementation of the visible print/write operations; buffer allocation/flush behavior is unrelated to this question. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.zig`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 5 | 32 | `    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);` |
| 6 | 13 | `    const out = &writer.interface;` |
| 7 | 48 | `    const names = [_][]const u8{ "milk", "notebook", "bread", "apple", "detergent", "eggs" };` |
| 8 | 45 | `    const prices = [_]u32{ 198, 165, 248, 128, 437, 268 };` |
| 9 | 33 | `    const quantities = [_]u32{ 2, 3, 1, 4, 1, 1 };` |
| 10 | 33 | `    const food = [_]bool{ true, false, true, true, false, true };` |
| 11 | 21 | `    var totals = [_]u32{ 0, 0 };` |
| 12 | 33 | `    for (names, prices, quantities, food) \|name, price, quantity, is_food\| {` |
| 13 | 15 | `        const subtotal = price * quantity;` |
| 14 | 31 | `        totals[if (is_food) @as(usize, 0) else 1] += subtotal;` |
| 15 | 51 | `        try out.print("{s} {d} x {d} = {d}\n", .{ name, price, quantity, subtotal });` |
| 16 | 3 | `    }` |
| 17 | 25 | `    const food_tax = totals[0] * 8 / 100;` |
| 18 | 26 | `    const general_tax = totals[1] * 10 / 100;` |
| 19 | 60 | `    try out.print("food: {d} yen, tax {d} yen\ngeneral: {d} yen, tax {d} yen\ntotal: {d} yen\n", .{` |
| 20 | 8 | `        totals[0],` |
| 21 | 7 | `        food_tax,` |
| 22 | 8 | `        totals[1],` |
| 23 | 7 | `        general_tax,` |
| 24 | 27 | `        totals[0] + totals[1] + food_tax + general_tax,` |
| 25 | 5 | `    });` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **531 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 601 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 533 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
