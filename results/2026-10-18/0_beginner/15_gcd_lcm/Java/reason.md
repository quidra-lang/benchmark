# Task B selection: 15_gcd_lcm / Java

## Common answer requirements

Trace (48,180) through Euclidean remainders and termination, connect returned GCD to LCM and identify division before multiplication, retaining original pair despite local gcd updates.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The successive (a,b) states are (48,180)→(180,48)→(48,36)→(36,12)→(12,0), with remainders48,36,12,0. The b!=0/nonzero loop stops when b reaches0 and returns a=12. The caller then computes (48/12)×180=4×180=720. Standard left associativity of division and multiplication, or explicit parentheses/division call, establishes that division occurs first. The Euclidean helper updates local numeric parameters; its caller still uses the original input pair.



Source: `Main.java`. Selected original lines: 2,3,4,5,6,7,8,12,13,14. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `    static int gcd(int a, int b) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `        while (b != 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `            int r = a % b;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `            a = b;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `            b = r;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L8: `        return a;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        for (int[] pair : new int[][]{{48, 180}, {1071, 462}, {7, 91}, {13, 97}, {36288, 98280}}) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            int a = pair[0], b = pair[1], g = gcd(a, b);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `            System.out.println("gcd(" + a + ", " + b + ") = " + g + ", lcm(" + a + ", " + b + ") = " + (a / g * b));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **289 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **327 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 270 tokens (versus 289); removes `static int gcd(int a, int b) {`.
- Without L3: 275 tokens (versus 289); removes `while (b != 0) {`.
- Without L4: 273 tokens (versus 289); removes `int r = a % b;`.
- Without L5: 279 tokens (versus 289); removes `a = b;`.
- Without L6: 279 tokens (versus 289); removes `b = r;`.
- Without L7: 285 tokens (versus 289); removes `}`.
- Without L8: 282 tokens (versus 289); removes `return a;`.
- Without L12: 209 tokens (versus 289); removes `for (int[] pair : new int[][]{{48, 180}, {1071, 462}, {7, 91}, {13, 97}, {36288, 98280}}) {`.
- Without L13: 251 tokens (versus 289); removes `int a = pair[0], b = pair[1], g = gcd(a, b);`.
- Without L14: 198 tokens (versus 289); removes `System.out.println("gcd(" + a + ", " + b + ") = " + g + ", lcm(" + a + ", " + b + ") = " + (a / g * b));`.
