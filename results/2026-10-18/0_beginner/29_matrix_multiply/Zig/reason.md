# Task B selection: 29_matrix_multiply / Zig

## Common answer requirements

Obtain the first row of A and second column of B from source, identify all four multiplied pairs, compute their sum, and establish row-major output and the second five-character field of output line one.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Row 1 of A is (3,−2,5,1); column 2 of B is (4,2,−1,7). The products are 12,−4,−5,7 and their sum is 10. The row loop visits row one first and the column loop visits column one then column two; the inner four-element dot product therefore supplies 10 to the second width-five integer field before the row newline. That field is three spaces followed by 10. Matrix multiplication primitives have the same row-column dot-product semantics.

The traced value 10 is nonnegative, so L14 plus the else and nonnegative print branch establish its field. The negative print expression is unnecessary for this trace.

Source: `main.zig`. Selected original lines: 7,8,9,10,11,12,13,14,16,17,18,19,20. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L7: `    const a = [_][4]i32{ .{ 3, -2, 5, 1 }, .{ -4, 7, 0, 6 }, .{ 2, 9, -8, -3 } };` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    const b = [_][2]i32{ .{ 1, 4 }, .{ -5, 2 }, .{ 6, -1 }, .{ 0, 7 } };` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    for (a) |row| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        for (0..2) |j| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            var value: i32 = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `            for (0..4) |k|` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `                value += row[k] * b[k][j];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `            if (value < 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `            } else {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L17: `                try out.print("{d:>5}", .{@as(u32, @intCast(value))});` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L19: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L20: `        try out.writeByte('\n');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **307 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **451 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L7: 234 tokens (versus 307); removes `const a = [_][4]i32{ .{ 3, -2, 5, 1 }, .{ -4, 7, 0, 6 }, .{ 2, 9, -8, -3 } };`.
- Without L8: 243 tokens (versus 307); removes `const b = [_][2]i32{ .{ 1, 4 }, .{ -5, 2 }, .{ 6, -1 }, .{ 0, 7 } };`.
- Without L9: 294 tokens (versus 307); removes `for (a) |row| {`.
- Without L10: 291 tokens (versus 307); removes `for (0..2) |j| {`.
- Without L11: 292 tokens (versus 307); removes `var value: i32 = 0;`.
- Without L12: 292 tokens (versus 307); removes `for (0..4) |k|`.
- Without L13: 283 tokens (versus 307); removes `value += row[k] * b[k][j];`.
- Without L14: 292 tokens (versus 307); removes `if (value < 0) {`.
- Without L16: 298 tokens (versus 307); removes `} else {`.
- Without L17: 269 tokens (versus 307); removes `try out.print("{d:>5}", .{@as(u32, @intCast(value))});`.
- Without L18: 302 tokens (versus 307); removes `}`.
- Without L19: 303 tokens (versus 307); removes `}`.
- Without L20: 291 tokens (versus 307); removes `try out.writeByte('\n');`.
