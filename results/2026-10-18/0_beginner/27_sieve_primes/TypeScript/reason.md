# Task B selection: 27_sieve_primes / TypeScript

## Common answer requirements

Explain initial primality of 7 and 49, how marking reaches 49 through p=7, why p itself is never crossed out, and how the resulting flags control membership in printed primes.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The initial table sets both 7 and 49 true. Processing p starts at 2 and considers true flags; marking starts at 2p and advances by p, so no prime marks itself. The smaller primes 2, 3, and 5 do not divide 7 or 49. At p=7 the multiples 14,21,28,35,42,49 are marked false. Hence 7 stays true and 49 becomes false. Output derives prime values from true flags and prints those values, retaining 7 and omitting 49.



Source: `main.ts`. Selected original lines: 1,2,4,5,6,7,8,9,10,11,13. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `const limit = 200;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `const isPrime = Array<boolean>(limit + 1).fill(true);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `for (let n = 2; n <= limit; n++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `  if (isPrime[n]) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    for (let multiple = n * 2; multiple <= limit; multiple += n) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `      isPrime[multiple] = false;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L9: `  }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L10: `}` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L11: `const primes = Array.from({length: limit - 1}, (_, i) => i + 2).filter(n => isPrime[n]);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `for (let start = 0; start < primes.length; start += 10) console.log(primes.slice(start, start + 10).join(" "));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **237 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **274 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 226 tokens (versus 237); removes `const limit = 200;`.
- Without L2: 212 tokens (versus 237); removes `const isPrime = Array<boolean>(limit + 1).fill(true);`.
- Without L4: 212 tokens (versus 237); removes `for (let n = 2; n <= limit; n++) {`.
- Without L5: 224 tokens (versus 237); removes `if (isPrime[n]) {`.
- Without L6: 204 tokens (versus 237); removes `for (let multiple = n * 2; multiple <= limit; multiple += n) {`.
- Without L7: 224 tokens (versus 237); removes `isPrime[multiple] = false;`.
- Without L8: 234 tokens (versus 237); removes `}`.
- Without L9: 234 tokens (versus 237); removes `}`.
- Without L10: 235 tokens (versus 237); removes `}`.
- Without L11: 185 tokens (versus 237); removes `const primes = Array.from({length: limit - 1}, (_, i) => i + 2).filter(n => isPrime[n]);`.
- Without L13: 180 tokens (versus 237); removes `for (let start = 0; start < primes.length; start += 10) console.log(primes.slice(start, start + 10).join(" "));`.
