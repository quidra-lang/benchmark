# Task B selection: 27_sieve_primes / Rust

## Common answer requirements

Explain initial primality of 7 and 49, how marking reaches 49 through p=7, why p itself is never crossed out, and how the resulting flags control membership in printed primes.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The initial table sets both 7 and 49 true. Processing p starts at 2 and considers true flags; marking starts at 2p and advances by p, so no prime marks itself. The smaller primes 2, 3, and 5 do not divide 7 or 49. At p=7 the multiples 14,21,28,35,42,49 are marked false. Hence 7 stays true and 49 becomes false. Output derives prime values from true flags and prints those values, retaining 7 and omitting 49.

The multi-line output expression requires group iteration, conversion, collection, and joining. No user helper is assumed; Vec/filter/chunks/map/join have standard semantics.

Source: `main.rs`. Selected original lines: 2,5,6,7,8,9,10,11,12,14,15,16,17,18,19,20,21. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `    let mut prime = [true; 201];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    for p in 2..=200 {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        if prime[p] {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `            for j in (2 * p..=200).step_by(p) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `                prime[j] = false;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L10: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L11: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L12: `    let primes: Vec<usize> = (2..=200).filter(|&n| prime[n]).collect();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    for group in primes.chunks(10) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `        println!(` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `            "{}",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `            group` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `                .iter()` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `                .map(usize::to_string)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `                .collect::<Vec<_>>()` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `                .join(" ")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **227 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **288 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 208 tokens (versus 227); removes `let mut prime = [true; 201];`.
- Without L5: 212 tokens (versus 227); removes `for p in 2..=200 {`.
- Without L6: 216 tokens (versus 227); removes `if prime[p] {`.
- Without L7: 197 tokens (versus 227); removes `for j in (2 * p..=200).step_by(p) {`.
- Without L8: 213 tokens (versus 227); removes `prime[j] = false;`.
- Without L9: 222 tokens (versus 227); removes `}`.
- Without L10: 223 tokens (versus 227); removes `}`.
- Without L11: 224 tokens (versus 227); removes `}`.
- Without L12: 188 tokens (versus 227); removes `let primes: Vec<usize> = (2..=200).filter(|&n| prime[n]).collect();`.
- Without L14: 210 tokens (versus 227); removes `for group in primes.chunks(10) {`.
- Without L15: 221 tokens (versus 227); removes `println!(`.
- Without L16: 218 tokens (versus 227); removes `"{}",`.
- Without L17: 222 tokens (versus 227); removes `group`.
- Without L18: 218 tokens (versus 227); removes `.iter()`.
- Without L19: 213 tokens (versus 227); removes `.map(usize::to_string)`.
- Without L20: 212 tokens (versus 227); removes `.collect::<Vec<_>>()`.
- Without L21: 215 tokens (versus 227); removes `.join(" ")`.
