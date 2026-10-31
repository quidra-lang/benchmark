# Task B selection: 15_gcd_lcm / Go

## Common answer requirements

Trace (48,180) through Euclidean remainders and termination, connect returned GCD to LCM and identify division before multiplication, retaining original pair despite local gcd updates.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The successive (a,b) states are (48,180)→(180,48)→(48,36)→(36,12)→(12,0), with remainders48,36,12,0. The b!=0/nonzero loop stops when b reaches0 and returns a=12. The caller then computes (48/12)×180=4×180=720. Standard left associativity of division and multiplication, or explicit parentheses/division call, establishes that division occurs first. The Euclidean helper updates local numeric parameters; its caller still uses the original input pair.



Source: `main.go`. Selected original lines: 5,6,7,8,9,13,14,15,16. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L5: `func gcd(a, b int64) int64 {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `	for b != 0 {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `		a, b = b, a%b` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `	}` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L9: `	return a` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `	for _, p := range [][2]int64{{48, 180}, {1071, 462}, {7, 91}, {13, 97}, {36288, 98280}} {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `		a, b := p[0], p[1]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `		g := gcd(a, b)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `		l := a / g * b` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **180 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **268 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L5: 164 tokens (versus 180); removes `func gcd(a, b int64) int64 {`.
- Without L6: 169 tokens (versus 180); removes `for b != 0 {`.
- Without L7: 164 tokens (versus 180); removes `a, b = b, a%b`.
- Without L8: 177 tokens (versus 180); removes `}`.
- Without L9: 175 tokens (versus 180); removes `return a`.
- Without L13: 101 tokens (versus 180); removes `for _, p := range [][2]int64{{48, 180}, {1071, 462}, {7, 91}, {13, 97}, {36288, 98280}} {`.
- Without L14: 160 tokens (versus 180); removes `a, b := p[0], p[1]`.
- Without L15: 166 tokens (versus 180); removes `g := gcd(a, b)`.
- Without L16: 164 tokens (versus 180); removes `l := a / g * b`.
