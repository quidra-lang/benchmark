# Task B selection: 41_quadratic_roots / Zig

## Common answer requirements

For (-2,5,4), derive discriminant and both quadratic-formula values; explain why the negative denominator makes the minus-root value larger; identify source ordering and its preservation in printed x1/x2.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The discriminant is 5²−4(−2)(4)=57>0. With denominator−4, the +sqrt value is (−5+sqrt57)/(−4)≈−0.6374586088 and the −sqrt value is (−5−sqrt57)/(−4)≈3.1374586088. Thus formula order alone is not descending. The selected max/min expressions or conditional swap explicitly put the larger value first; x1 prints 3.1375 and x2 prints −0.6375 with four fractional digits. The distinct-real branch is selected because 57 is positive.



Source: `main.zig`. Selected original lines: 8,10-16,18-22. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L8: `        .{ 1, -3, -10 }, .{ -2, 5, 4 }, .{ 3, 1, -2 }, .{ 4, -12, 9 }, .{ 1, 2, 5 }, .{ -2, 3, -4 },` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    for (sets) |s| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        const a = s[0];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        const b = s[1];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `        const c = s[2];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        const disc = b * b - 4 * a * c;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `        const numerator = -@as(f64, @floatFromInt(b));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `        const denominator = 2.0 * @as(f64, @floatFromInt(a));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `        if (disc > 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `            const root = @sqrt(@as(f64, @floatFromInt(disc)));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `            const r1 = (numerator + root) / denominator;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `            const r2 = (numerator - root) / denominator;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `            try out.print("x1 = {d:.4}, x2 = {d:.4}", .{ @max(r1, r2), @min(r1, r2) });` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **378 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **774 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L8: 283 tokens (versus 378); removes `.{ 1, -3, -10 }, .{ -2, 5, 4 }, .{ 3, 1, -2 }, .{ 4, -12, 9 }, .{ 1, 2, 5 }, .{ -2, 3, -4 },`.
- Without L10: 365 tokens (versus 378); removes `for (sets) |s| {`.
- Without L11: 364 tokens (versus 378); removes `const a = s[0];`.
- Without L12: 364 tokens (versus 378); removes `const b = s[1];`.
- Without L13: 364 tokens (versus 378); removes `const c = s[2];`.
- Without L14: 351 tokens (versus 378); removes `const disc = b * b - 4 * a * c;`.
- Without L15: 353 tokens (versus 378); removes `const numerator = -@as(f64, @floatFromInt(b));`.
- Without L16: 348 tokens (versus 378); removes `const denominator = 2.0 * @as(f64, @floatFromInt(a));`.
- Without L18: 364 tokens (versus 378); removes `if (disc > 0) {`.
- Without L19: 349 tokens (versus 378); removes `const root = @sqrt(@as(f64, @floatFromInt(disc)));`.
- Without L20: 356 tokens (versus 378); removes `const r1 = (numerator + root) / denominator;`.
- Without L21: 356 tokens (versus 378); removes `const r2 = (numerator - root) / denominator;`.
- Without L22: 319 tokens (versus 378); removes `try out.print("x1 = {d:.4}, x2 = {d:.4}", .{ @max(r1, r2), @min(r1, r2) });`.
