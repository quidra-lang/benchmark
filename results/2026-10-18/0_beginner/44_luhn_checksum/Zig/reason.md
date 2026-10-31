# Task B selection: 44_luhn_checksum / Zig

## Common answer requirements

Explain leading-zero preservation of 0128469655154 as a digit string through validation/output; identify alternating doubled positions counting from the right; explain expected replacement of the rightmost check digit on failure.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The membership value is stored as text, including its leading0, and output uses that original text. Individual character-to-digit conversions create arithmetic values without converting/replacing the full string. Counting from the right with check digit at position1, double positions2,4,6,8,10,12; equivalently use odd zero-based reverse indices, or even length−i for a forward zero-based scan. Values above9 after doubling lose9. For this number, transformed digits from the right are 4,1,1,1,5,3,9,3,4,7,2,2,0, totaling42, so validation fails. Subtract the undoubled rightmost4 to get38; the nonnegative modulo-10 complement gives expected check digit2. Reporting keeps the original leading-zero string.



Source: `main.zig`. Selected original lines: 7,9,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L7: `    const numbers = [_][]const u8{` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        "0128469655154",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `    for (numbers) |number| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `        var sum: u32 = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `        for (number, 0..) |c, i| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `            var v: u32 = c - '0';` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `            if ((number.len - i) % 2 == 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `                v *= 2;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `                if (v > 9)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `                    v -= 9;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L24: `            sum += v;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L25: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L26: `        try out.print("{s}: ", .{number});` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L27: `        if (sum % 10 == 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L28: `            try out.writeAll("valid\n");` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L29: `        } else {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L30: `            const without = sum - (number[number.len - 1] - '0');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L31: `            const expected = (10 - without % 10) % 10;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L32: `            try out.print("invalid (expected check digit {d})\n", .{expected});` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **351 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **580 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L7: 335 tokens (versus 351); removes `const numbers = [_][]const u8{`.
- Without L9: 332 tokens (versus 351); removes `"0128469655154",`.
- Without L15: 338 tokens (versus 351); removes `for (numbers) |number| {`.
- Without L16: 337 tokens (versus 351); removes `var sum: u32 = 0;`.
- Without L17: 330 tokens (versus 351); removes `for (number, 0..) |c, i| {`.
- Without L18: 331 tokens (versus 351); removes `var v: u32 = c - '0';`.
- Without L19: 324 tokens (versus 351); removes `if ((number.len - i) % 2 == 0) {`.
- Without L20: 340 tokens (versus 351); removes `v *= 2;`.
- Without L21: 337 tokens (versus 351); removes `if (v > 9)`.
- Without L22: 339 tokens (versus 351); removes `v -= 9;`.
- Without L23: 346 tokens (versus 351); removes `}`.
- Without L24: 341 tokens (versus 351); removes `sum += v;`.
- Without L25: 347 tokens (versus 351); removes `}`.
- Without L26: 328 tokens (versus 351); removes `try out.print("{s}: ", .{number});`.
- Without L27: 332 tokens (versus 351); removes `if (sum % 10 == 0) {`.
- Without L28: 333 tokens (versus 351); removes `try out.writeAll("valid\n");`.
- Without L29: 343 tokens (versus 351); removes `} else {`.
- Without L30: 318 tokens (versus 351); removes `const without = sum - (number[number.len - 1] - '0');`.
- Without L31: 322 tokens (versus 351); removes `const expected = (10 - without % 10) % 10;`.
- Without L32: 316 tokens (versus 351); removes `try out.print("invalid (expected check digit {d})\n", .{expected});`.
