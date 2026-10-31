# Task B selection: 27_sieve_primes / Lua

## Common answer requirements

Explain initial primality of 7 and 49, how marking reaches 49 through p=7, why p itself is never crossed out, and how the resulting flags control membership in printed primes.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The initial table sets both 7 and 49 true. Processing p starts at 2 and considers true flags; marking starts at 2p and advances by p, so no prime marks itself. The smaller primes 2, 3, and 5 do not divide 7 or 49. At p=7 the multiples 14,21,28,35,42,49 are marked false. Hence 7 stays true and 49 becomes false. Output derives prime values from true flags and prints those values, retaining 7 and omitting 49.



Source: `main.lua`. Selected original lines: 1,2,3,4,5,6,7,9,10,11,13,14. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `local limit, prime = 200, {}` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `for n = 0, limit do prime[n] = n >= 2 end` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `for p = 2, limit do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    if prime[p] then` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        for multiple = 2 * p, limit, p do prime[multiple] = false end` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L7: `end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L9: `for n = 2, limit do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    if prime[n] then primes[#primes + 1] = n end` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L13: `for first = 1, #primes, 10 do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    io.write(table.concat(primes, " ", first, math.min(first + 9, #primes)), "\n")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **208 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **243 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 191 tokens (versus 208); removes `local limit, prime = 200, {}`.
- Without L2: 180 tokens (versus 208); removes `for n = 0, limit do prime[n] = n >= 2 end`.
- Without L3: 195 tokens (versus 208); removes `for p = 2, limit do`.
- Without L4: 198 tokens (versus 208); removes `if prime[p] then`.
- Without L5: 175 tokens (versus 208); removes `for multiple = 2 * p, limit, p do prime[multiple] = false end`.
- Without L6: 205 tokens (versus 208); removes `end`.
- Without L7: 206 tokens (versus 208); removes `end`.
- Without L9: 195 tokens (versus 208); removes `for n = 2, limit do`.
- Without L10: 182 tokens (versus 208); removes `if prime[n] then primes[#primes + 1] = n end`.
- Without L11: 206 tokens (versus 208); removes `end`.
- Without L13: 190 tokens (versus 208); removes `for first = 1, #primes, 10 do`.
- Without L14: 165 tokens (versus 208); removes `io.write(table.concat(primes, " ", first, math.min(first + 9, #primes)), "\n")`.
