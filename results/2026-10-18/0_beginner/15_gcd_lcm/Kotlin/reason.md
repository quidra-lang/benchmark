# Task B selection: 15_gcd_lcm / Kotlin

## Common answer requirements

Trace (48,180) through Euclidean remainders and termination, connect returned GCD to LCM and identify division before multiplication, retaining original pair despite local gcd updates.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The successive (a,b) states are (48,180)→(180,48)→(48,36)→(36,12)→(12,0), with remainders48,36,12,0. The b!=0/nonzero loop stops when b reaches0 and returns a=12. The caller then computes (48/12)×180=4×180=720. Standard left associativity of division and multiplication, or explicit parentheses/division call, establishes that division occurs first. The Euclidean helper updates local numeric parameters; its caller still uses the original input pair.

The x=a,y=b locals connect the helper’s mutated state to its parameters and returned x; they cannot change caller values.

Source: `main.kt`. Selected original lines: 1,2,3,4,5,6,7,8,9,13,14,15. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `fun gcd(a: Int, b: Int): Int {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    var x = a` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    var y = b` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    while (y != 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        val r = x % y` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        x = y` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        y = r` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L9: `    return x` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    for ((a, b) in listOf(48 to 180, 1071 to 462, 7 to 91, 13 to 97, 36288 to 98280)) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        val g = gcd(a, b)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `        println("gcd($a, $b) = $g, lcm($a, $b) = ${a / g * b}")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **225 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **241 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 206 tokens (versus 225); removes `fun gcd(a: Int, b: Int): Int {`.
- Without L2: 216 tokens (versus 225); removes `var x = a`.
- Without L3: 216 tokens (versus 225); removes `var y = b`.
- Without L4: 212 tokens (versus 225); removes `while (y != 0) {`.
- Without L5: 211 tokens (versus 225); removes `val r = x % y`.
- Without L6: 217 tokens (versus 225); removes `x = y`.
- Without L7: 217 tokens (versus 225); removes `y = r`.
- Without L8: 222 tokens (versus 225); removes `}`.
- Without L9: 220 tokens (versus 225); removes `return x`.
- Without L13: 152 tokens (versus 225); removes `for ((a, b) in listOf(48 to 180, 1071 to 462, 7 to 91, 13 to 97, 36288 to 98280)) {`.
- Without L14: 209 tokens (versus 225); removes `val g = gcd(a, b)`.
- Without L15: 177 tokens (versus 225); removes `println("gcd($a, $b) = $g, lcm($a, $b) = ${a / g * b}")`.
