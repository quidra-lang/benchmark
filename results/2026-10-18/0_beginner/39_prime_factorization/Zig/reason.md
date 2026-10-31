# Task B selection: 39_prime_factorization / Zig

## Common answer requirements

Trace trial division for supplied value 9973, show why remainder stays unchanged and the square-bound stop occurs, then explain residual-factor insertion and exact output without exponent or separator.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

No integer divisor 2 through 99 divides 9973 (equivalently none of the primes through 97 does), so every remainder test fails and no division/exponent increment happens. Since 99²=9801 <=9973 but 100²=10000 >9973, the trial loop stops at divisor 100 with remainder still 9973. The ordinary-factor positive-exponent branch is never entered. The residual >1 path inserts/prints 9973 directly, without an exponent. An initially empty factor list joins its sole entry with no separator, or an initially true first flag suppresses the separator. The full line is `9973 = 9973` followed by newline.

The exponent>0 guard prevents first=false; the residual branch sees first still true and skips the separator. Its direct integer print carries no exponent.

Source: `main.zig`. Selected original lines: 7,8,9,10,11,12,13,14,15,16,17,18,21,25,26,27,28,29,30,32. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L7: `    for ([_]u64{ 84, 9973, 15625, 1001, 123456, 48000, 999958, 999999 }) |n| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        try out.print("{d} = ", .{n});` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        var remaining = n;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        var d: u64 = 2;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        var first = true;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        while (d * d <= remaining) : (d += 1) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            var exponent: u32 = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `            while (remaining % d == 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `                remaining /= d;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `                exponent += 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L18: `            if (exponent > 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `                first = false;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L25: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L26: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L27: `        if (remaining > 1) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L28: `            if (!first)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L29: `                try out.writeAll(" * ");` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L30: `            try out.print("{d}", .{remaining});` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L32: `        try out.writeByte('\n');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **338 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **555 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L7: 266 tokens (versus 338); removes `for ([_]u64{ 84, 9973, 15625, 1001, 123456, 48000, 999958, 999999 }) |n| {`.
- Without L8: 313 tokens (versus 338); removes `try out.print("{d} = ", .{n});`.
- Without L9: 327 tokens (versus 338); removes `var remaining = n;`.
- Without L10: 325 tokens (versus 338); removes `var d: u64 = 2;`.
- Without L11: 327 tokens (versus 338); removes `var first = true;`.
- Without L12: 310 tokens (versus 338); removes `while (d * d <= remaining) : (d += 1) {`.
- Without L13: 323 tokens (versus 338); removes `var exponent: u32 = 0;`.
- Without L14: 319 tokens (versus 338); removes `while (remaining % d == 0) {`.
- Without L15: 327 tokens (versus 338); removes `remaining /= d;`.
- Without L16: 327 tokens (versus 338); removes `exponent += 1;`.
- Without L17: 333 tokens (versus 338); removes `}`.
- Without L18: 323 tokens (versus 338); removes `if (exponent > 0) {`.
- Without L21: 327 tokens (versus 338); removes `first = false;`.
- Without L25: 333 tokens (versus 338); removes `}`.
- Without L26: 334 tokens (versus 338); removes `}`.
- Without L27: 324 tokens (versus 338); removes `if (remaining > 1) {`.
- Without L28: 328 tokens (versus 338); removes `if (!first)`.
- Without L29: 319 tokens (versus 338); removes `try out.writeAll(" * ");`.
- Without L30: 315 tokens (versus 338); removes `try out.print("{d}", .{remaining});`.
- Without L32: 322 tokens (versus 338); removes `try out.writeByte('\n');`.
