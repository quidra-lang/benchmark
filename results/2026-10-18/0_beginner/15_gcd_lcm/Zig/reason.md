# Task B selection: 15_gcd_lcm / Zig

## Common answer requirements

Trace (48,180) through Euclidean remainders and termination, connect returned GCD to LCM and identify division before multiplication, retaining original pair despite local gcd updates.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The successive (a,b) states are (48,180)→(180,48)→(48,36)→(36,12)→(12,0), with remainders48,36,12,0. The b!=0/nonzero loop stops when b reaches0 and returns a=12. The caller then computes (48/12)×180=4×180=720. Standard left associativity of division and multiplication, or explicit parentheses/division call, establishes that division occurs first. The Euclidean helper updates local numeric parameters; its caller still uses the original input pair.

first/second map to local a/b, whose updates do not mutate caller p. The explicit division parentheses establish the required LCM order.

Source: `main.zig`. Selected original lines: 3,4,5,6,7,8,9,10,11,18,19,20,21. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L3: `fn gcd(first: u64, second: u64) u64 {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    var a = first;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    var b = second;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    while (b != 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        const r = a % b;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        a = b;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        b = r;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L11: `    return a;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `    const pairs = [_][2]u64{ .{ 48, 180 }, .{ 1071, 462 }, .{ 7, 91 }, .{ 13, 97 }, .{ 36288, 98280 } };` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `    for (pairs) |p| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `        const g = gcd(p[0], p[1]);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `        const l = (p[0] / g) * p[1];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **250 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **457 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L3: 230 tokens (versus 250); removes `fn gcd(first: u64, second: u64) u64 {`.
- Without L4: 240 tokens (versus 250); removes `var a = first;`.
- Without L5: 240 tokens (versus 250); removes `var b = second;`.
- Without L6: 237 tokens (versus 250); removes `while (b != 0) {`.
- Without L7: 235 tokens (versus 250); removes `const r = a % b;`.
- Without L8: 241 tokens (versus 250); removes `a = b;`.
- Without L9: 241 tokens (versus 250); removes `b = r;`.
- Without L10: 247 tokens (versus 250); removes `}`.
- Without L11: 244 tokens (versus 250); removes `return a;`.
- Without L18: 158 tokens (versus 250); removes `const pairs = [_][2]u64{ .{ 48, 180 }, .{ 1071, 462 }, .{ 7, 91 }, .{ 13, 97 }, .{ 36288, 98280 } };`.
- Without L19: 237 tokens (versus 250); removes `for (pairs) |p| {`.
- Without L20: 227 tokens (versus 250); removes `const g = gcd(p[0], p[1]);`.
- Without L21: 223 tokens (versus 250); removes `const l = (p[0] / g) * p[1];`.
