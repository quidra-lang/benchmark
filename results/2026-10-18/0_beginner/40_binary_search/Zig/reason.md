# Task B selection: 40_binary_search / Zig

## Common answer requirements

Trace search for 50 using actual array values, initial/inclusive bounds, midpoint and comparison updates; list zero-based probes, stopping bounds and failure-state output; derive complete printed line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Start lo=0, hi=15. Probe 7 reads31<50, so lo=8; probe11 reads53>50, so hi=10; probe9 reads42<50, so lo=10; probe10 reads47<50, so lo=11. Now lo=11>hi=10 and the inclusive-bound loop stops. No equality assignment ever changes the initial not-found state. Probe recording/printing preserves that order; the full line is `50: probes 7 11 9 10 -> not found` followed by newline. One-based storage implementations explicitly access mid+1 while still recording zero-based mid.

The optional found starts null. @divTrunc agrees with floor here because the examined sums are nonnegative; null chooses the final else output.

Source: `main.zig`. Selected original lines: 7,8,9,10,11,12,13,14,15,16,17,18,20,21,22,23,24,25,26,28,29. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L7: `    const a = [_]i32{ 3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77 };` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    for ([_]i32{ 42, 3, 77, 31, 50, 1 }) |target| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        var lo: i32 = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        var hi: i32 = 15;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        var found: ?i32 = null;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        try out.print("{d}: probes", .{target});` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `        while (lo <= hi) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `            const mid = @divTrunc(lo + hi, 2);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `            try out.print(" {d}", .{mid});` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `            const value = a[@intCast(mid)];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `            if (value == target) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `                found = mid;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `            } else if (value < target) {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L21: `                lo = mid + 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `            } else {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L23: `                hi = mid - 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L25: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L26: `        if (found) |index| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L28: `        } else {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L29: `            try out.writeAll(" -> not found\n");` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **405 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **564 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L7: 328 tokens (versus 405); removes `const a = [_]i32{ 3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77 };`.
- Without L8: 365 tokens (versus 405); removes `for ([_]i32{ 42, 3, 77, 31, 50, 1 }) |target| {`.
- Without L9: 391 tokens (versus 405); removes `var lo: i32 = 0;`.
- Without L10: 390 tokens (versus 405); removes `var hi: i32 = 15;`.
- Without L11: 390 tokens (versus 405); removes `var found: ?i32 = null;`.
- Without L12: 381 tokens (versus 405); removes `try out.print("{d}: probes", .{target});`.
- Without L13: 391 tokens (versus 405); removes `while (lo <= hi) {`.
- Without L14: 381 tokens (versus 405); removes `const mid = @divTrunc(lo + hi, 2);`.
- Without L15: 381 tokens (versus 405); removes `try out.print(" {d}", .{mid});`.
- Without L16: 385 tokens (versus 405); removes `const value = a[@intCast(mid)];`.
- Without L17: 390 tokens (versus 405); removes `if (value == target) {`.
- Without L18: 394 tokens (versus 405); removes `found = mid;`.
- Without L20: 386 tokens (versus 405); removes `} else if (value < target) {`.
- Without L21: 390 tokens (versus 405); removes `lo = mid + 1;`.
- Without L22: 396 tokens (versus 405); removes `} else {`.
- Without L23: 390 tokens (versus 405); removes `hi = mid - 1;`.
- Without L24: 400 tokens (versus 405); removes `}`.
- Without L25: 401 tokens (versus 405); removes `}`.
- Without L26: 391 tokens (versus 405); removes `if (found) |index| {`.
- Without L28: 397 tokens (versus 405); removes `} else {`.
- Without L29: 382 tokens (versus 405); removes `try out.writeAll(" -> not found\n");`.
