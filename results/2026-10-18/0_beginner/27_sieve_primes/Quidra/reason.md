# Task B selection: 27_sieve_primes / Quidra

## Common answer requirements

Explain initial primality of 7 and 49, how marking reaches 49 through p=7, why p itself is never crossed out, and how the resulting flags control membership in printed primes.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The initial table sets both 7 and 49 true. Processing p starts at 2 and considers true flags; marking starts at 2p and advances by p, so no prime marks itself. The smaller primes 2, 3, and 5 do not divide 7 or 49. At p=7 the multiples 14,21,28,35,42,49 are marked false. Hence 7 stays true and 49 becomes false. Output derives prime values from true flags and prints those values, retaining 7 and omitting 49.



Source: `main.qui`. Selected original lines: 1,4-7,9-11,13,16. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `bool[] prime = array(201, fill = true)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `for 2 <= int p <= 200` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    if prime[p]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        for 2 * p <= int multiple <= 200 step p` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `            prime[multiple] = false` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `for 2 <= int n <= 200` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    if prime[n]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        primes = primes.append(n)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `for nat i < len(primes)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `    print(primes[i])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **142 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **246 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 121 tokens (versus 142); removes `bool[] prime = array(201, fill = true)`.
- Without L4: 126 tokens (versus 142); removes `for 2 <= int p <= 200`.
- Without L5: 134 tokens (versus 142); removes `if prime[p]`.
- Without L6: 116 tokens (versus 142); removes `for 2 * p <= int multiple <= 200 step p`.
- Without L7: 130 tokens (versus 142); removes `prime[multiple] = false`.
- Without L9: 126 tokens (versus 142); removes `for 2 <= int n <= 200`.
- Without L10: 134 tokens (versus 142); removes `if prime[n]`.
- Without L11: 129 tokens (versus 142); removes `primes = primes.append(n)`.
- Without L13: 129 tokens (versus 142); removes `for nat i < len(primes)`.
- Without L16: 133 tokens (versus 142); removes `print(primes[i])`.
