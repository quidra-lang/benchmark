# Task B selection: 15_gcd_lcm / Swift

## Common answer requirements

Trace (48,180) through Euclidean remainders and termination, connect returned GCD to LCM and identify division before multiplication, retaining original pair despite local gcd updates.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The successive (a,b) states are (48,180)→(180,48)→(48,36)→(36,12)→(12,0), with remainders48,36,12,0. The b!=0/nonzero loop stops when b reaches0 and returns a=12. The caller then computes (48/12)×180=4×180=720. Standard left associativity of division and multiplication, or explicit parentheses/division call, establishes that division occurs first. The Euclidean helper updates local numeric parameters; its caller still uses the original input pair.



Source: `main.swift`. Selected original lines: 1,2,3,4,5,6,9,10,11. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `func gcd(_ a: Int, _ b: Int) -> Int {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    var x = a, y = b` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    while y != 0 {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `        (x, y) = (y, x % y)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L6: `    return x` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `for (a, b) in [(48, 180), (1071, 462), (7, 91), (13, 97), (36288, 98280)] {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    let g = gcd(a, b)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    print("gcd(\(a), \(b)) = \(g), lcm(\(a), \(b)) = \(a / g * b)")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **226 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **231 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 202 tokens (versus 226); removes `func gcd(_ a: Int, _ b: Int) -> Int {`.
- Without L2: 210 tokens (versus 226); removes `var x = a, y = b`.
- Without L3: 215 tokens (versus 226); removes `while y != 0 {`.
- Without L4: 204 tokens (versus 226); removes `(x, y) = (y, x % y)`.
- Without L5: 223 tokens (versus 226); removes `}`.
- Without L6: 221 tokens (versus 226); removes `return x`.
- Without L9: 153 tokens (versus 226); removes `for (a, b) in [(48, 180), (1071, 462), (7, 91), (13, 97), (36288, 98280)] {`.
- Without L10: 211 tokens (versus 226); removes `let g = gcd(a, b)`.
- Without L11: 169 tokens (versus 226); removes `print("gcd(\(a), \(b)) = \(g), lcm(\(a), \(b)) = \(a / g * b)")`.
