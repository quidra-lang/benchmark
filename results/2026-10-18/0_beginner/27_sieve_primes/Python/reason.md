# Task B selection: 27_sieve_primes / Python

## Common answer requirements

Explain initial primality of 7 and 49, how marking reaches 49 through p=7, why p itself is never crossed out, and how the resulting flags control membership in printed primes.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The initial table sets both 7 and 49 true. Processing p starts at 2 and considers true flags; marking starts at 2p and advances by p, so no prime marks itself. The smaller primes 2, 3, and 5 do not divide 7 or 49. At p=7 the multiples 14,21,28,35,42,49 are marked false. Hence 7 stays true and 49 becomes false. Output derives prime values from true flags and prints those values, retaining 7 and omitting 49.



Source: `main.py`. Selected original lines: 1-2,4-8,10-11. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `limit = 200` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `is_prime = [True] * (limit + 1)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `for n in range(2, limit + 1):` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    if is_prime[n]:` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        for multiple in range(n * 2, limit + 1, n):` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `            is_prime[multiple] = False` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `primes = [n for n in range(2, limit + 1) if is_prime[n]]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `for start in range(0, len(primes), 10):` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    print(*primes[start : start + 10])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **174 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **210 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 166 tokens (versus 174); removes `limit = 200`.
- Without L2: 154 tokens (versus 174); removes `is_prime = [True] * (limit + 1)`.
- Without L4: 155 tokens (versus 174); removes `for n in range(2, limit + 1):`.
- Without L5: 164 tokens (versus 174); removes `if is_prime[n]:`.
- Without L6: 146 tokens (versus 174); removes `for multiple in range(n * 2, limit + 1, n):`.
- Without L7: 160 tokens (versus 174); removes `is_prime[multiple] = False`.
- Without L8: 140 tokens (versus 174); removes `primes = [n for n in range(2, limit + 1) if is_prime[n]]`.
- Without L10: 152 tokens (versus 174); removes `for start in range(0, len(primes), 10):`.
- Without L11: 155 tokens (versus 174); removes `print(*primes[start : start + 10])`.
