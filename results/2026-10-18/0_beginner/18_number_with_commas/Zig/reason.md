# Task B selection: 18_number_with_commas / Zig

## Common answer requirements

Trace -456789 to its exact grouped output, identify right-based three-digit boundaries and sign placement, and explain why sign is excluded and no comma follows it.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The magnitude digits are456789, partitioned from the right into456|789, so the output line is `-456,789` followed by newline. Manual implementations strip/skip the sign or format the absolute magnitude, print/prepend minus separately, and insert a comma only before a nonfirst digit whose remaining digit count is divisible by3. This gives the one boundary before7; a guard excluding the first digit prevents a comma immediately after minus. Regex/library implementations perform equivalent numeric-digit grouping, preserving minus as sign rather than including it as a digit.



Source: `main.zig`. Selected original lines: 7,9,10,11,12,13,14,15,16,17. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L7: `    for ([_]i64{ 0, 7, 999, 1000, -456789, 3141592, 9876543210 }) |n| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        const digits = try std.fmt.bufPrint(&buf, "{d}", .{@abs(n)});` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        if (n < 0)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            try out.writeByte('-');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        for (digits, 0..) |c, i| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            if (i > 0 and (digits.len - i) % 3 == 0)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `                try out.writeByte(',');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `            try out.writeByte(c);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L17: `        try out.writeByte('\n');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **237 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **373 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L7: 172 tokens (versus 237); removes `for ([_]i64{ 0, 7, 999, 1000, -456789, 3141592, 9876543210 }) |n| {`.
- Without L9: 198 tokens (versus 237); removes `const digits = try std.fmt.bufPrint(&buf, "{d}", .{@abs(n)});`.
- Without L10: 225 tokens (versus 237); removes `if (n < 0)`.
- Without L11: 221 tokens (versus 237); removes `try out.writeByte('-');`.
- Without L12: 216 tokens (versus 237); removes `for (digits, 0..) |c, i| {`.
- Without L13: 204 tokens (versus 237); removes `if (i > 0 and (digits.len - i) % 3 == 0)`.
- Without L14: 220 tokens (versus 237); removes `try out.writeByte(',');`.
- Without L15: 223 tokens (versus 237); removes `try out.writeByte(c);`.
- Without L16: 233 tokens (versus 237); removes `}`.
- Without L17: 221 tokens (versus 237); removes `try out.writeByte('\n');`.
