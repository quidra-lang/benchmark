# Task B selection: 27_sieve_primes / Java

## Common answer requirements

Explain initial primality of 7 and 49, how marking reaches 49 through p=7, why p itself is never crossed out, and how the resulting flags control membership in printed primes.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The initial table sets both 7 and 49 true. Processing p starts at 2 and considers true flags; marking starts at 2p and advances by p, so no prime marks itself. The smaller primes 2, 3, and 5 do not divide 7 or 49. At p=7 the multiples 14,21,28,35,42,49 are marked false. Hence 7 stays true and 49 becomes false. Output derives prime values from true flags and prints those values, retaining 7 and omitting 49.



Source: `Main.java`. Selected original lines: 7,8,10,11,12,13,14,15,16,18,19,20,21,22,24,25. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L7: `        boolean[] prime = new boolean[201];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        Arrays.fill(prime, true);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        for (int p = 2; p <= 200; p++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            if (prime[p]) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `                for (int m = 2 * p; m <= 200; m += p) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `                    prime[m] = false;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `                }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L15: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L16: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L18: `        for (int n = 2; n <= 200; n++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `            if (prime[n]) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `                primes.add(Integer.toString(n));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L22: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L24: `        for (int i = 0; i < primes.size(); i += 10) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L25: `            System.out.println(String.join(" ", primes.subList(i, Math.min(i + 10, primes.size()))));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **297 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **424 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L7: 278 tokens (versus 297); removes `boolean[] prime = new boolean[201];`.
- Without L8: 284 tokens (versus 297); removes `Arrays.fill(prime, true);`.
- Without L10: 268 tokens (versus 297); removes `for (int p = 2; p <= 200; p++) {`.
- Without L11: 283 tokens (versus 297); removes `if (prime[p]) {`.
- Without L12: 259 tokens (versus 297); removes `for (int m = 2 * p; m <= 200; m += p) {`.
- Without L13: 282 tokens (versus 297); removes `prime[m] = false;`.
- Without L14: 291 tokens (versus 297); removes `}`.
- Without L15: 292 tokens (versus 297); removes `}`.
- Without L16: 293 tokens (versus 297); removes `}`.
- Without L18: 268 tokens (versus 297); removes `for (int n = 2; n <= 200; n++) {`.
- Without L19: 283 tokens (versus 297); removes `if (prime[n]) {`.
- Without L20: 279 tokens (versus 297); removes `primes.add(Integer.toString(n));`.
- Without L21: 292 tokens (versus 297); removes `}`.
- Without L22: 293 tokens (versus 297); removes `}`.
- Without L24: 262 tokens (versus 297); removes `for (int i = 0; i < primes.size(); i += 10) {`.
- Without L25: 248 tokens (versus 297); removes `System.out.println(String.join(" ", primes.subList(i, Math.min(i + 10, primes.size()))));`.
