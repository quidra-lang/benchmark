# Task B selection: 27_sieve_primes / J

## Common answer requirements

Explain initial primality of 7 and 49, how marking reaches 49 through p=7, why p itself is never crossed out, and how the resulting flags control membership in printed primes.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The initial table sets both 7 and 49 true. Processing p starts at 2 and considers true flags; marking starts at 2p and advances by p, so no prime marks itself. The smaller primes 2, 3, and 5 do not divide 7 or 49. At p=7 the multiples 14,21,28,35,42,49 are marked false. Hence 7 stays true and 49 becomes false. Output derives prime values from true flags and prints those values, retaining 7 and omitting 49.

L6 forms p * (2 + i.(floor(200/p)-1)) under J evaluation, enumerating multipliers starting at 2; I. selects true indices.

Source: `main.ijs`. Selected original lines: 2,4,5,6,7,8,9,10,12,13. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `  prime =. 201$1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `  for_p. 2+i.199 do.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    if. p{prime do.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `      multiples =. p * 2 + i. <: <. 200 % p` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `      prime =. 0 multiples}prime` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    end.` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L9: `  end.` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L10: `  primes =. I.prime` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `  for_start. 10*i. >. (#primes)%10 do.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    smoutput ": (10 <. (#primes)-start) {. start}.primes` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **139 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **189 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 128 tokens (versus 139); removes `prime =. 201$1`.
- Without L4: 124 tokens (versus 139); removes `for_p. 2+i.199 do.`.
- Without L5: 130 tokens (versus 139); removes `if. p{prime do.`.
- Without L6: 111 tokens (versus 139); removes `multiples =. p * 2 + i. <: <. 200 % p`.
- Without L7: 127 tokens (versus 139); removes `prime =. 0 multiples}prime`.
- Without L8: 136 tokens (versus 139); removes `end.`.
- Without L9: 136 tokens (versus 139); removes `end.`.
- Without L10: 130 tokens (versus 139); removes `primes =. I.prime`.
- Without L12: 116 tokens (versus 139); removes `for_start. 10*i. >. (#primes)%10 do.`.
- Without L13: 113 tokens (versus 139); removes `smoutput ": (10 <. (#primes)-start) {. start}.primes`.
